--[[
    Name: lua-stream-and-log-v3.lua
    Desc: This example shows how to stream data to AIN0 and log to file
    Note: Streams at 4KS/s, using nominal cal constants

          This example requires firmware 1.0282 (T7) or 1.0023 (T4)

          T-Series datasheet on streaming:
            https://labjack.com/support/datasheets/t7/communication/stream-mode/low-level-streaming
--]]

print("Stream and log AIN0 at 1kS/s to file, nominal cal constants")

-- Disable truncation warnings (truncation is not a problem in this script)
MB.writeName("LUA_NO_WARN_TRUNCATION", 1)

-- Check what hardware is installed
local hardware = MB.readName("HARDWARE_INSTALLED")

local data = {}

-- Create or open and overwrite the file
local filename = "logFile.csv"
local file = io.open(filename, "w")

-- Make sure that the file was opened properly.
if file then
  print("Opened File on uSD Card", filename)
else
  -- If the file was not opened properly we probably have a bad SD card.
  print("!! Failed to open file on uSD Card !!", filename)
  MB.writeName("LUA_RUN", 0)
end

--debug interval
local streamread = 0
local interval = 100

-- Make sure analog is on
MB.writeName("POWER_AIN", 1)

-- Make sure streaming is not enabled
local streamrunning = MB.readName("STREAM_ENABLE")
if streamrunning == 1 then
  MB.writeName("STREAM_ENABLE", 0)
end

-- AIN config
MB.writeName("AIN_ALL_RANGE", 10) -- Use +-10V for the AIN range
MB.writeName("STREAM_SCANRATE_HZ", 1000) -- Use a 1000Hz scanrate
MB.writeName("STREAM_NUM_ADDRESSES", 1) -- Use 1 channel for streaming
MB.writeName("STREAM_SETTLING_US", 1) -- Enforce a 1uS settling time
MB.writeName("STREAM_RESOLUTION_INDEX", 8) -- Use the default stream resolution
MB.writeName("STREAM_BUFFER_SIZE_BYTES", 2^11) -- Use a 1024 byte buffer size (must be a power of 2)
MB.writeName("STREAM_AUTO_TARGET", 16) -- Use command-response mode (0b10000=16)
MB.writeName("STREAM_NUM_SCANS", 0) -- Run continuously (can be limited)
MB.writeName("STREAM_SCANLIST_ADDRESS0", 0) -- Scan AIN0
MB.writeName("STREAM_ENABLE", 1) -- Start the stream

--check every 5ms
LJ.IntervalConfig(0, 5)

local numinbuffer = 1

--run until FIO2 is low
while MB.readName("FIO2") >= .5 do
  -- If an interval is done
  if LJ.CheckInterval(0) then
    
    -- 4 (header) + 1 (num channels)
    local numtoread = 4 + numinbuffer
    data = MB.readNameArray("STREAM_DATA_CR", numtoread, 0)
    
    -- get the number of samples remaining in the buffer
    numinbuffer = data[2]
    
    -- make sure there arent too many samples in buffer
    if numinbuffer > 100 then
      print("TOO MANY DATA")
      numinbuffer = 100
    end
    
    -- loop through data read from buffer
    for i=5, numtoread do
      
      -- Notify user of a stream error.
      if data[i] == 0xFFFF then
        print("Bad Val", data[3],data[4])
      end
      
      --write data to file
      file:write(string.format("%.4f\n", data[i]))
    end
    
    --debug every n reads
    streamread = streamread + 1
    if streamread%interval == 0 then
      print(streamread, numinbuffer, data[2])
    end
  end
end

--end script
file:flush()
file:close()
print("Finishing Script", filename)
MB.writeName("LUA_RUN", 0)

