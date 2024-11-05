 -- This code is to record strain gauges to file on labjack
 -- For automatic amplification: Even AIN ports (ie. AIN0) = positive signal, Odd AIN ports (ie. AIN1) = negative signal 
-- Strain Gauges need external amplification - do not connect it to the labjack
-- Tie the strain gauge to ground (from the external amplification) to the labjack ground


-- FILL OUT THESE VARIABLES ACCORDING TO THE STRAIN GAUGES BEING USED
local ratedLoad = 2000     --
local exciteVolt = 5      -- External voltage used to excite the SGs (usually 10-12 volts)

print("Strain Gauge - Log voltage to file")

-- Check for SD card
local hardware = MB.R(60010, 1)
local passed = 1
if(bit.band(hardware, 8) ~= 8) then
  print("uSD card not detected")
  passed = 0
end

-- Initialize variables/functions
local mbRead=MB.R			--local functions for faster processing
local mbWrite = MB.W
local mbneg_chan = MB.nameToAddress("AIN_ALL_NEGATIVE_CHANNEL")
fio0Address, fio0DataType = MB.nameToAddress("FIO0")
fio1Address, fio1DataType = MB.nameToAddress("FIO1")
local ain = 0
local strain = 0
local newData = 0
local count = 0
local delimiter = ","
local ainStr = ""
local strainStr = ""

-- Configure AIN ports
local ainchannels = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14}    -- AIN0 and AIN1 for ports
local ainrange = 10     -- +/- 10V input range
local ainresolution = 1   -- 1 is fastest setting
local ainsettling = 0   -- default settling time
--for i=1, table.getn(ainchannels) do
  --ain_channel_config(ainchannels[i], ainrange, ainresolution, ainsettling)
--end

MB.W(48005, 0, 1)                       --ensure analog is on
MB.W(mbneg_chan,1)                      --set all channels to differential

-- To end the entire script, click the button
local scriptEnd = 0
scriptEnd = mbRead(2000, 0) --FIO0

while scriptEnd >= 0.5 do
  -- Create and open file for write access
  local cntStr = tostring(count)
  local Filename = cntStr .. ".csv"
  local file = io.open(Filename, "w")

  -- Make sure that the file was opened properly.
  if file then
    print("Opened File on uSD Card")
  else
    -- If the file was not opened properly we probably have a bad SD card.
    print("!! Failed to open file on uSD Card !! \n Stoping script")
    MB.W(6000, 1, 0);
  end
  
  -- Set interval to 1000 for 1000ms
  LJ.IntervalConfig(0, 1000)
  local checkInterval=LJ.CheckInterval
  
   -- Read FIO2 (2002) state
  newData = mbRead(2002, 0)
  
   repeat
    if newData <= 0.5 then
      if checkInterval(0) then      --if sleep is 1sec
        print("Waiting for button to be pressed")

        newData = mbRead(2001, 0) --FIO1
        scriptEnd = mbRead(2000, 0) --FIO0

        if scriptEnd < 0.5 then
          print("Finished Script")
          MB.W(6000, 1, 0);
        end
      end
    end
  until newData < 0.5
  
  -- NewData button has been pressed - start recording data
  while newData < 0.5 do
    if checkInterval(0) then     	    --interval completed
      ain_list = ""
      for i=1, table.getn(ainchannels) do
        if ainchannels[i]%2 == 0 then
          ain = mbRead(ainchannels[i],3)
          strain = 4*ain/(2.1*(exciteVolt - 2*ain))
          ain_list = ain_list.append(string.format("%.6f", strain))
        end
      end
      
      -- Write data to file
      file:write(ain_list, "\n")

      -- Check status of newData button
      newData = mbRead(2001, 0)

    end
    if newData >= 0.5 then
      break
    end
  end
  
  -- Close current working file
  file:close()
  print("Done with log. \n")
  count = count + 1

  -- Check scriptEnd button status
  scriptEnd = mbRead(2000, 0) --FIO0

  -- If the scriptEnd button has been pressed
  if scriptEnd < 0.5 then
    print("Finished Script")
    MB.W(6000, 1, 0);
  end
end
  
  
