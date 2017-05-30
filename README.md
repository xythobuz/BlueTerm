# BlueTerm

This is a small macOS Objective-C command line application. It uses CoreBluetooth to connect to a Bluetooth 4.0 Low Energy UART bridge, like the [HM-10](http://fab.cba.mit.edu/classes/863.15/doc/tutorials/programming/bluetooth.html).

All received data will be written to a logfile.

# Quickstart

Edit `BlueTerm/main.m` and at least change the Bluetooth device name to your setting. You may also need to change the UART service and characteristic UUID, depending on the specific hardware you're using.

    git clone https://github.com/xythobuz/BlueTerm.git
    cd BlueTerm
    xcodebuild
    ./build/Release/BlueTerm

By default, all received data will be written to `~/BlueTerm.log`, but you can specify another location as a command line parameter.

## Licensing

This project is heavily based on [this gist by Brayden Morris](https://gist.github.com/brayden-morris-303/09a738ed9c83a7d14c82). Therefore it is released under the public domain.

