Sensor Tag Logger
=================

This iOS app logs data from two [Texas Instruments CC2650 SensorTag](http://www.ti.com/tool/TIDC-CC2650STK-SENSORTAG). The intention is to have those tags be mounted somewhere on a human body.

Some inspiration for this app came from [anasimtiaz/SwiftSensorTag](https://github.com/anasimtiaz/SwiftSensorTag).


Server for Storing Logged Data
------------------------------

The app periodically uploads the data to a server with an HTTP POST request.  [A very simple server](./server) provides the necessary functionality.
