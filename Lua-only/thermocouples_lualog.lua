--Lua script for logging thermocouples
print("Lua script for logging thermocouples type E")

-- Check for SD card
local hardware = MB.R(60010, 1)
local passed = 1
if(bit.band(hardware, 8) ~= 8) then
  print("uSD card not detected")
  passed = 0
end

-- Initialize variables/functions
local mbRead=MB.R			
local mbWrite = MB.W

-- AIN#_EF_INDEX values for each thermocouple type
local tctypes = {}
tctypes["E"] = 20
tctypes["J"] = 21
tctypes["K"] = 22
tctypes["R"] = 23
tctypes["T"] = 24
tctypes["S"] = 25
tctypes["C"] = 30
-- AIN#_EF_CONFIG_A values corresponding to their temperature units
local tempunits = {}
tempunits["K"] = 0
tempunits["C"] = 1
tempunits["F"] = 2
-- Enable AINs
local ainchannels = {0, 2, 4,6,8,10,12}
local ain_names = "Stator Cover, Left Floor near Cool Pipe, EVO, Collector, Shor Right, Clutch Cover, Headers \n"
local tctype = "E"
local tempunit = "C"
-- Use the devices internal temp sensor, TEMPERATURE_DEVICE_K
local cjcaddress = 60052
local range = 0.1
local resolution = 8
-- Use default settling time
local settling = 0
local isdifferential = true
local readconfaddressa = MB.nameToAddress("AIN0_EF_READ_A")


local function ain_channel_config(ainchannel, range, resolution, settling, isdifferential)
  local rangeaddress = MB.nameToAddress("AIN0_RANGE")
  local resaddress = MB.nameToAddress("AIN0_RESOLUTION_INDEX")
  local setaddress = MB.nameToAddress("AIN0_SETTLING_US")
  local negchaddress = MB.nameToAddress("AIN0_NEGATIVE_CH")
  -- Set AIN range
  MB.W(rangeaddress + ainchannel * 2, 3, range)
  -- Set resolution index
  MB.W(resaddress + ainchannel * 1, 0, resolution)
  -- Set settling time
  MB.W(setaddress + ainchannel * 2, 3, settling)

  -- Read the device type
  local devicetype = MB.readName("PRODUCT_ID")
  -- Setup the negative channel if using a differential input
  if isdifferential and (ainchannel%2 == 0) and (devicetype == 7) then
    -- The negative channels setting is only valid for even
    if (ainchannel < 14) then
      -- The negative channel is 1+ the channel for AIN0-13
      MB.W(negchaddress + ainchannel, 0, ainchannel + 1)
    elseif (ainchannel > 47) then
      -- The negative channel is 8+ the channel for AIN48-127 when using a Mux80
      MB.W(negchaddress + ainchannel, 0, ainchannel + 8)
    else
      print(string.format("Can not set negative channel for AIN%d",ainchannel))
    end
  end
end

-- Extended Features -> tctype is E
local function ain_ef_config_tc(ainchannel, tctype, unit, cjcaddressess, cjcslope, cjcoffset)
  local indexaddress = MB.nameToAddress("AIN0_EF_INDEX")
  local confaddressa = MB.nameToAddress("AIN0_EF_CONFIG_A")
  local confaddressb = MB.nameToAddress("AIN0_EF_CONFIG_B")
  local confaddressd = MB.nameToAddress("AIN0_EF_CONFIG_D")
  local confaddresse = MB.nameToAddress("AIN0_EF_CONFIG_E")
  local negchaddress = MB.nameToAddress("AIN0_NEGATIVE_CH")
  -- Disable AIN_EF
  --MB.W(indexaddress + ainchannel * 2, 1, 0)
  -- Enable AIN_EF
  MB.W(indexaddress + ainchannel * 2, 1, tctype)
  -- Write to AIN_EF_CONFIG_A
  MB.W(confaddressa + ainchannel * 2, 1, unit)
  -- Write to AIN_EF_CONFIG_B
  MB.W(confaddressb + ainchannel * 2, 1, cjcaddressess)
  -- Write to AIN_EF_CONFIG_D
  MB.W(confaddressd + ainchannel * 2, 3, cjcslope)
  -- Write to AIN_EF_CONFIG_E
  MB.W(confaddresse + ainchannel * 2, 3, cjcoffset)
end

-- Configure each analog input
for i=1,table.getn(ainchannels) do
  ain_channel_config(ainchannels[i],range,resolution,settling,isdifferential)
  ain_ef_config_tc(ainchannels[i],tctypes[tctype],tempunits[tempunit],cjcaddress,1.0,0.0)
end


-- Set interval to 1000 for 1000 ms
  LJ.IntervalConfig(0, 1000)
  local checkInterval=LJ.CheckInterval

-- To end the entire script, click the button
local scriptEnd = 1
scriptEnd = mbRead(2000, 0) --FIO0
local count = 0

while scriptEnd <= 0.5 do
  -- Create and open file for write access
  local cntStr = tostring(count)
  local Filename = cntStr .. ".csv"
  local file = io.open(Filename, "w")

  -- Make sure that the file was opened properly
  if file then
    print("Opened File on uSD Card")
    file:write(ain_names)
  else
    -- If the file was not opened properly we probably have a bad SD card
    print("!! Failed to open file on uSD Card !! \n Stoping script")
    MB.W(6000, 1, 0);
  end
  
  
   -- Read FIO2 (2002) state
  newData = mbRead(2002, 0)
  
  
  repeat
    if newData >= 0.5 then
      --if sleep is 1 sec
      if checkInterval(0) then
        print("Waiting for button to be pressed")
        
        --FIO2
        newData = mbRead(2002, 0)
        --FIO0
        scriptEnd = mbRead(2000, 0)

        if scriptEnd > 0.5 then
          print("Finished Script")
          MB.W(6000, 1, 0);
        end
      end
    end
  until newData < 0.5
  
  -- NewData button has been pressed, start recording data
  while newData < 0.5 do
      -- If an interval is done
    if LJ.CheckInterval(0) then
      -- Read & Print out each read AIN channel
      local temp_str = ""
      for i=1, table.getn(ainchannels) do
        local temperature = MB.R(readconfaddressa + ainchannels[i] * 2, 3)
        print(string.format("Temperature: %.3f %s", temperature, tempunit))
        temp_str = temp_str..(string.format("%.3f",temperature)..",")
      end
      file:write(temp_str,"\n")
    end
      
    -- Check status of newData button
    newData = mbRead(2002, 0)
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
  if scriptEnd > 0.5 then
    print("Finished Script")
    -- Write 0 to LUA_RUN to stop the script
    MB.writeName("LUA_RUN", 0);
    MB.W(6000, 1, 0);
  end
end
