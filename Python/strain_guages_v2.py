"""
Demonstrates how to stream using the eStream functions.

Relevant Documentation:

LJM Library:
    LJM Library Installer:
        https://labjack.com/support/software/installers/ljm
    LJM Users Guide:
        https://labjack.com/support/software/api/ljm
    Opening and Closing:
        https://labjack.com/support/software/api/ljm/function-reference/opening-and-closing
    Constants:
        https://labjack.com/support/software/api/ljm/constants
    Stream Functions:
        https://labjack.com/support/software/api/ljm/function-reference/stream-functions

T-Series and I/O:
    Modbus Map:
        https://labjack.com/support/software/api/modbus/modbus-map
    Stream Mode:
        https://labjack.com/support/datasheets/t-series/communication/stream-mode
    Analog Inputs:
        https://labjack.com/support/datasheets/t-series/ain

Note:
    Our Python interfaces throw exceptions when there are any issues with
    device communications that need addressed. Many of our examples will
    terminate immediately when an exception is thrown. The onus is on the API
    user to address the cause of any exceptions thrown, and add exception
    handling when appropriate. We create our own exception classes that are
    derived from the built-in Python Exception class and can be caught as such.
    For more information, see the implementation in our source code and the
    Python standard documentation.
"""
from datetime import datetime
import sys

from labjack import ljm


MAX_REQUESTS = 10  # The number of eStreamRead calls that will be performed.

# Open LabJack
handle = ljm.openS("T7", "ANY", "ANY")  # T7 device, Any connection, Any identifier

info = ljm.getHandleInfo(handle)
print("Opened a LabJack with Device type: %i, Connection type: %i,\n"
      "Serial number: %i, IP address: %s, Port: %i,\nMax bytes per MB: %i" %
      (info[0], info[1], info[2], ljm.numberToIP(info[3]), info[4], info[5]))

deviceType = info[0]

# Stream Configuration
streamedChannels = strainGaugeChannels = [0]
inputVoltageChannel = 10
streamedChannels.append(inputVoltageChannel)
numAddresses = len(streamedChannels)

streamedChannelNames = [f"AIN{channel}" for channel in streamedChannels] #convert to names (AIN#)
aScanList = ljm.namesToAddresses(numAddresses, streamedChannelNames)[0]

scanRate = 100 #scans per second per channel
secondsPerRead = .5
scansPerRead = int(scanRate / numAddresses * secondsPerRead)

try:
    # Ensure triggered stream is disabled.
    ljm.eWriteName(handle, "STREAM_TRIGGER_INDEX", 0)
    # Enabling internally-clocked stream.
    ljm.eWriteName(handle, "STREAM_CLOCK_SOURCE", 0)

    # make channel configurations
    settingsNames = []
    settingsValues = []
    for channel in strainGaugeChannels:
        settingsNames.extend([f"AIN{channel}_RANGE", f"AIN{channel + 1}_RANGE", f"AIN{channel}_NEGATIVE_CH"])
        settingsValues.extend([1, 10.0, channel + 1])
    
    settingsNames.extend([f"AIN{inputVoltageChannel}_RANGE", f"AIN{inputVoltageChannel}_NEGATIVE_CH"])
    settingsValues.extend([10.0, 199]) #negative channel is ground

    settingsNames.extend(["STREAM_SETTLING_US", "STREAM_RESOLUTION_INDEX"])
    settingsValues.extend([0, 8])

    # write the channel configs
    numFrames = len(settingsNames)
    ljm.eWriteNames(handle, numFrames, settingsNames, settingsValues)

    # Configure and start stream
    scanRate = ljm.eStreamStart(handle, scansPerRead, numAddresses, aScanList, scanRate)
    print("\nStream started with a scan rate of %0.0f Hz." % scanRate)

    start = datetime.now()
    totalScans = 0
    totalSkip = 0  # Total skipped samples

    i = 1
    while i <= MAX_REQUESTS:
        ret = ljm.eStreamRead(handle)
        print(ret)
        aData = ret[scansPerRead]
        scans = len(aData) / numAddresses
        totalScans += scans

        # Count the skipped samples which are indicated by -9999 values. Missed
        # samples occur after a device's stream buffer overflows and are
        # reported after auto-recover mode ends.
        curSkip = aData.count(-9999.0)
        totalSkip += curSkip

        print("\neStreamRead %i" % i)
        ainStr = ""
        for j in range(0, numAddresses):
            ainStr += "%0.5f, " % (aData[j])
        print(ainStr)
        #print("  Scans Skipped = %0.0f, Scan Backlogs: Device = %i, LJM = " "%i" % (curSkip/numAddresses, ret[1], ret[2]))
        i += 1

    end = datetime.now()

    print("\nTotal scans = %i" % (totalScans))
    tt = (end - start).seconds + float((end - start).microseconds) / 1000000
    print("Time taken = %f seconds" % (tt)) 
    print("LJM Scan Rate = %f scans/second" % (scanRate))
    print("Timed Scan Rate = %f scans/second" % (totalScans / tt))
    print("Timed Sample Rate = %f samples/second" % (totalScans * numAddresses / secondsPerRead / tt))
    print("Skipped scans = %0.0f" % (totalSkip / numAddresses))
except ljm.LJMError:
    ljme = sys.exc_info()[1]
    print(ljme)
except Exception as e:
    print(e)

try:
    print("\nStop Stream")
    ljm.eStreamStop(handle)
except ljm.LJMError:
    ljme = sys.exc_info()[1]
    print(ljme)
except Exception:
    e = sys.exc_info()[1]
    print(e)

# Close handle
ljm.close(handle)