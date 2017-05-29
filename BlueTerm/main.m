//
//  main.m
//  BlueTerm
//
//  Created by Thomas Buck on 29.05.17.
//  Copyright © 2017 Thomas Buck. All rights reserved.
//  xythobuz@xythobuz.de
//
//  Heavily based on:
//  https://gist.github.com/brayden-morris-303/09a738ed9c83a7d14c82
//
//  This utility connects to a common Bluetooth 4.0 BLE UART bridge
//  and logs all received data to the local filesystem.
//  This has been developed for use as a Betaflight blackbox replacement.

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

// ---------------------------------------------------------------------------------------

// BLE UART device name that is searched for
static NSString * const kDeviceName = @"xyCopter";

// BLE Service & Characteristic UUIDs for the UART data stream
static NSString * const kUARTServiceUUID = @"ffe0";
static NSString * const kUARTCharacteristicUUID = @"ffe1";

// Default log file path, if no command line argument is given
static NSString * const kDefaultFilePath = @"~/BlueTerm.log";

// ---------------------------------------------------------------------------------------

@interface BlueTerm : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate>

@property (strong, nonatomic) CBCentralManager *centralManager;
@property (strong, nonatomic) CBPeripheral *discoveredPeripheral;
@property (assign) BOOL shouldRun;
@property (strong, nonatomic) NSFileHandle *fileHandle;

@end

@implementation BlueTerm

- (id)init {
    if (self = [super init]) {
        self.shouldRun = false;
        self.centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
        return self;
    }
    return nil;
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    if (!self.shouldRun) return;
    
    // You should test all scenarios
    if (central.state != CBCentralManagerStatePoweredOn) {
        NSLog(@"Unknown BLE state: %ld", (long)central.state);
        return;
    }
    
    if (central.state == CBCentralManagerStatePoweredOn) {
        // Scan for devices
        [self.centralManager scanForPeripheralsWithServices:@[[CBUUID UUIDWithString:kUARTServiceUUID]] options:@{ CBCentralManagerScanOptionAllowDuplicatesKey : @YES }];
        NSLog(@"Scanning started...");
    }
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI {
    
    NSLog(@"Discovered %@ at %@", peripheral.name, RSSI);
    
    if (([peripheral.name isEqualToString:kDeviceName]) && (self.discoveredPeripheral != peripheral)) {
        // Save a local copy of the peripheral, so CoreBluetooth doesn't get rid of it
        self.discoveredPeripheral = peripheral;
        
        // And connect
        NSLog(@"Connecting to peripheral %@", peripheral);
        [self.centralManager connectPeripheral:peripheral options:nil];
    }
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    NSLog(@"Connected");
    
    [_centralManager stopScan];
    NSLog(@"Scanning stopped");
    
    peripheral.delegate = self;
    
    [peripheral discoverServices:@[[CBUUID UUIDWithString:kUARTServiceUUID]]];
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    if (error) {
        NSLog(@"Error: %@", error);
        return;
    }
    
    for (CBService *service in peripheral.services) {
        NSLog(@"Discovered service: %@", service.UUID);
        
        if ([service.UUID isEqual:[CBUUID UUIDWithString:kUARTServiceUUID]]) {
            NSLog(@"This is our service. Discovering characteristics...");
            
            [peripheral discoverCharacteristics:@[[CBUUID UUIDWithString:kUARTCharacteristicUUID]] forService:service];
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    if (error) {
        return;
    }
    
    for (CBCharacteristic *characteristic in service.characteristics) {
        NSLog(@"Discovered characteristic: %@", characteristic.UUID);
        
        if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:kUARTCharacteristicUUID]]) {
            NSLog(@"This is our characteristic! Subscribing...");
            
            [peripheral setNotifyValue:YES forCharacteristic:characteristic];
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (error) {
        return;
    }
    
    static time_t lastTime = 0;
    time_t now = time(NULL);
    if ((now - lastTime) > 0) {
        NSString *valueString = [[[[NSString alloc] initWithData:characteristic.value encoding:NSUTF8StringEncoding] stringByReplacingOccurrencesOfString:@"\n" withString:@""] stringByReplacingOccurrencesOfString:@"\r" withString:@""];
        NSLog(@"Received more data (excerpt: \"%@\")", valueString);
        lastTime = now;
    }
    
    [self.fileHandle writeData:characteristic.value];
}

- (BOOL)initializeTargetFile:(int)argc withParams:(const char **)argv {
    NSString *filePath;
    if (argc == 1) {
        // Use hard-coded default path
        filePath = [kDefaultFilePath stringByExpandingTildeInPath];
    } else if (argc == 2) {
        // Use given path
        filePath = [[NSString stringWithCString:argv[1] encoding:NSUTF8StringEncoding] stringByExpandingTildeInPath];
    } else {
        NSLog(@"Usage:\n\t%@ [/path/to/log]", [NSString stringWithCString:argv[0] encoding:NSUTF8StringEncoding]);
        return false;
    }
    
    [[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil];
    self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    if (self.fileHandle) {
        NSLog(@"Writing received data to: \"%@\"!", filePath);
        NSLog(@"File has been overwritten (if it existed before)!");
        [self.fileHandle seekToEndOfFile];
    } else {
        NSLog(@"Error opening logfile: \"%@\"!", filePath);
        return false;
    }
    
    self.shouldRun = true;
    return true;
}

- (void)cleanup {
    if (self.discoveredPeripheral) {
        if ([self.discoveredPeripheral state] != CBPeripheralStateDisconnected) {
            NSLog(@"Disconnecting from device...");
            [self.centralManager cancelPeripheralConnection:self.discoveredPeripheral];
        }
    }
    
    if (self.fileHandle) {
        NSLog(@"Closing logfile...");
        [self.fileHandle closeFile];
        self.fileHandle = nil;
    }
    
    exit(0);
}

@end

BlueTerm *bt;

void signalHandler(int sig) {
    [bt cleanup];
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"Initializing BlueTerm...");
        if (signal(SIGINT, signalHandler) == SIG_ERR) {
            NSLog(@"Error, can't catch SIGINT...");
            return 1;
        }
        
        bt = [[BlueTerm alloc] init];
        if (![bt initializeTargetFile:argc withParams:argv]) {
            return 2;
        }
        
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
