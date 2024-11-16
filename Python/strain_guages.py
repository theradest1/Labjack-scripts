import datetime
import sys
from labjack import ljm
import os
import time

#functions
def getSwitchState(handle, name):
    return ljm.eReadName(handle, name) < .5

# LabJack T7 configuration
handle = ljm.openS("T7", "USB", "ANY")
info = ljm.getHandleInfo(handle)
print("Opened a LabJack with Device type: %i, Connection type: %i,\n" \
      "Serial number: %i, IP address: %s, Port: %i,\nMax bytes per MB: %i" % \
      (info[0], info[1], info[2], ljm.numberToIP(info[3]), info[4], info[5]))

deviceType = info[0]
MAX_REQUESTS = 10  # The number of eStreamRead calls that will be performed.

# Setup AINs
# AIN0
name0 = "AIN0"
readName0 = "AIN0_READ_A"

# AIN1
name1 = "AIN1"
readName1 = "AIN1_READ_A"

# Stream Configuration
aScanListNames = ["AIN0", "AIN1"]  # Scan list names to stream
numAddresses = len(aScanListNames)
aScanList = ljm.namesToAddresses(numAddresses, aScanListNames)[0]
scanRate = 10000 # was 10000
sampleTime = 10
scansPerRead = int(sampleTime*scanRate) #int(scanRate / 2)

# Ensure triggered stream is disabled.
ljm.eWriteName(handle, "STREAM_TRIGGER_INDEX", 0)
# Enabling internally-clocked stream.
ljm.eWriteName(handle, "STREAM_CLOCK_SOURCE", 0)

# AIN0 and AIN1 ranges are +/-10 V and stream resolution index is
# 0 (default).
aNames = ["AIN0_RANGE", "AIN1_RANGE", "STREAM_RESOLUTION_INDEX"]
aValues = [10.0, 10.0, 0]

# Negative Channel = 199 (Single-ended)
# Settling = 0 (auto)
aNames.extend(["AIN0_NEGATIVE_CH", "STREAM_SETTLING_US","AIN1_NEGATIVE_CH"]) #
aValues.extend([199, 0, 199])

# Write the analog inputs' negative channels (when applicable), ranges,
# stream settling time and stream resolution configuration.
numFrames = len(aNames)
ljm.eWriteNames(handle, numFrames, aNames, aValues)

# Get the current working directory and create folder if needed
folder = "logs"
cwd_folder = os.getcwd() + '\\' + folder

if not os.path.exists(cwd_folder):
    os.makedirs(cwd_folder)

cwd = cwd_folder
while getSwitchState(handle, "FIO0"):

    print("Waiting until switch is on")
    while not getSwitchState(handle, "FIO2"):
        pass

    # Get the current time to build a time-stamp
    startTime = datetime.datetime.now()
    fileDateTime = startTime.strftime("%Y-%m-%d_%I-%M-%S") # year-month-day hour:minute:second.microsecond
    
    # Build a file-name and the file path.
    fileName = "%s-SG-%iHz.csv" % (fileDateTime, scanRate)
    filePath = os.path.join(cwd, fileName)

    
    # Open the file and write a header line
    with open(filePath, 'w') as logFile:
        #log while switch on FIO2 is on
        while getSwitchState(handle, "FIO2"):

                header = "Date/Time, Accel, Hammer\n"
                logFile.write(header)

                time_st = time.time()
                print("This is time_st: ", time_st)
                ljm.eStreamStart(handle, scansPerRead, numAddresses, aScanList, scanRate)
                start_time = ljm.eReadName(handle, "STREAM_START_TIME_STAMP")
                print("Stream started at %f Hz\n" % scanRate)
                data_list = []
                time_list = []
                totScans = 0
                totSkip = 0  # Total skipped samples

                ret = ljm.eStreamRead(handle)
                time_list.append(time.time())
                aData = ret[0]
                print(aData)
                data_list.append(aData)
                scans = len(aData) / numAddresses
                totScans += scans
                #print("scans: %f, totScans: %i" % (scans, totScans))
                timer = totScans * (1/scanRate)

                # Count the skipped samples which are indicated by -9999 values. Missed
                # samples occur after a device's stream buffer overflows and are
                # reported after auto-recover mode ends.
                curSkip = aData.count(-9999.0)
                totSkip += curSkip
                print("This is totSkip :", totSkip)

                ljm.eStreamStop(handle)
                end_timer = time.time()
                print("This is end_timer: ", end_timer)

                print("Starting to read")
                for h in range(len(data_list)):
                    packet_Time = time_list[h] - time_st
                    dataTime = 0
                    timeDifference = 2 * (packet_Time / len(data_list[h])) #has twice the data in the list
                    alt = -1
                    for l in range(len(data_list[h]) - 1):
                        if alt == -1:
                            if data_list[h][l] != -9999.0 and data_list[h][l+1] != -9999.0:
                                logFile.write("%f, %f, %f\n" % (dataTime, data_list[h][l], data_list[h][l+1]))
                                alt = 1
                            dataTime = dataTime + timeDifference
                        else:
                            alt = alt * -1

        # force flush data to file
        logFile.flush()

    print("File Closed")

    # End data acq for current folder
    try:
        print("\nStop Stream")
        ljm.eStreamStop(handle)
    except ljm.LJMError:
        ljme = sys.exc_info()[1]
        print(ljme)
    except Exception:
        e = sys.exc_info()[1]
        print(e)

    print("Stopped Stream")

# Close the interval and device handles
#ljm.cleanInterval(intervalHandle)
ljm.close(handle)
print("Script finished")