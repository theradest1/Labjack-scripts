 -- This code is to record strain gauges to file on labjack
 -- For automatic amplification: Even AIN ports (ie. AIN0) = positive signal, Odd AIN ports (ie. AIN1) = negative signal 
-- Strain Gauges need external amplification - do not connect it to the labjack
-- Tie the strain gauge to ground (from the external amplification) to the labjack ground

-- FILL OUT THESE VARIABLES ACCORDING TO THE STRAIN GAUGES BEING USED
local exciteVolt = 5      -- External voltage used to excite the SGs (usually 10-12 volts)
local nominal = 120 -- 120 or 350 ohms
local elasticModulus = 29000000 --elastic modulus for arms is 29m
local gaugeFactor = 26--2.12 -- based on the strain gauges
local logInterval = 50 --in ms

print("Strain Gauge - Log voltage to file")

-- Check for SD card
if(bit.band(MB.R(60010, 1), 8) ~= 8) then
  print("uSD card not detected")
  stopProgram()
end

-- Initialize local functions (for faster processing)
local mbRead=MB.R
local mbWrite = MB.W
local mbReadName = MB.readName
local mbWriteName = MB.writeName
local mbNameToAddress = MB.nameToAddress
local checkInterval=LJ.CheckInterval
local setInterval = LJ.IntervalConfig

-- Initialize variables
local waitingInterval = 250 --how much time between checks of when loggin should start
local safeState = 1 -- 1 if file isn't being written to
local ledState = 1

local newData = 1
local givenVoltage = 0

local zeroAin = 0

local sgResistance = 0
local sgResistanceDiff = 0
local voltageDiff = 0
local stress = 0
local ainChannel = 0

local delimiter = ","
local stressString = ""

-- AIN port config
local ainChannelCorrection = {0}--, 0, 0, 0, 0} --values that zero each channel
local ainChannels = {0}--, 4, 6, 8, 10} -- the channels that are read (only even because the odds are the negative channels)
local givenVoltageChannel = 2
local ainVoltageRange = 10 -- +/- 1V input range
local ainResolution = 12 -- 1 is fastest, 12 is most detail
local ainSettlingTime = 0 -- default settling time

-- functions
local function configureChannel(channel, range, resolution, settling)
  --get base addresses
  rangeaddress = mbNameToAddress("AIN0_RANGE")
  resaddress = mbNameToAddress("AIN0_RESOLUTION_INDEX")
  setaddress = mbNameToAddress("AIN0_SETTLING_US")
  negchaddress = mbNameToAddress("AIN0_NEGATIVE_CH")
  
  -- set config
  mbWrite(rangeaddress + channel * 2, 3, range)
  mbWrite(resaddress + channel * 1, 0, resolution)
  mbWrite(setaddress + channel * 2, 3, settling)
  mbWrite(negchaddress + channel, 0, channel + 1)
end

local function updateDebugLED()
  if(safeState == 1) then
    ledState = 0 -- stay on
  else
    ledState = 1 - ledState -- turn on and off
  end
  
  MB.writeName("FIO1", ledState) -- set lcd
end

local function setSafeState(newState)
  safeState = newState -- record state
  
  updateDebugLED() -- update led
end

local function stopProgram(message)
  message = message or "Script was stopped" -- default message
  print(message) --print message
  
  mbWriteName("FIO1", 1) --set lcd state to off
  mbWriteName("LUA_RUN", 0); -- write 0
  mbWrite(6000, 1, 0); -- stop
end

local function getLogFileName()
  local timetable, error = MB.readNameArray("RTC_TIME_CALENDAR", 6)
  return string.format(
    "%04d-%02d-%02d-%02d-%02d-%02d.csv",
    timetable[1],
    timetable[2],
    timetable[3],
    timetable[4],
    timetable[5],
    timetable[6])
end

local function zeroChannels()
  setInterval(0, 50)
  setSafeState(0)
  
  print("\nZeroing channels")
  while zeroAin < 0.5 do
    if LJ.CheckInterval() then
      updateDebugLED()
      
      zeroAin = mbRead(2000, 0) --FIO0
    end
  end
  
  for i=1, table.getn(ainChannels) do --loop through channels
    ain = mbReadName("AIN" .. ainChannels[i], 3) --get value
    
    ainChannelCorrection[i] = -ain -- set correction to -value
  end
  
  setSafeState(1)
  print("\nChannel correction:\n", table.concat(ainChannelCorrection, delimiter))
end

--loop through strain gauge ain channels
for i=1,table.getn(ainChannels) do
  configureChannel(ainChannels[i], ainVoltageRange, ainResolution, ainSettingTime)
end
--configureChannel(givenVoltageChannel, 10, 1, 0) --input voltage muesure ain channel

while true do --loop forever
  setSafeState(1) --set default state
  
  -- Set waiting interval
  setInterval(0, waitingInterval)
  
  print("\nWaiting for button to be pressed")
  while newData >= 0.5 do
    if checkInterval() then

      --check if user wants to zero channels
      zeroAin = mbRead(2000, 0) --FIO0
      if zeroAin < 0.5 then
        zeroChannels()
      end
      
      newData = mbRead(2002, 0) --FIO2
    end
  end
  
  -- Create and open file for write access
  local Filename = getLogFileName()
  setSafeState(0) -- set mode to unsafe
  local file = io.open(Filename, "w")

  -- Make sure that the file was opened properly.
  if file then
    print("\nCreated and opened debug file with name " .. Filename .. "\n")
  else
    -- If the file was not opened properly we probably have a bad SD card.
    stopProgram("!! Failed to open file on uSD Card !! \n Stoping script\n")
  end
  print("Logging data:")
  
  file:write("sg1, sg2, sg3, sg4, sg5", "\n") -- Write header to file
  
  -- Set logging interval
  setInterval(0, logInterval)
  
  -- NewData button has been pressed - start recording data
  while newData < 0.5 do
    if checkInterval() then
      updateDebugLED()
      stressString = ""
      diffString = ""
      
      for i=1,table.getn(ainChannels) do
        -- get variable values
        givenVoltage = mbReadName("AIN" .. givenVoltageChannel, 3) -- get Vs
        voltageDiff = mbReadName("AIN" .. ainChannels[i], 3) -- get voltage diff
        
        voltageDiff = voltageDiff + ainChannelCorrection[i] -- correct voltage input
        
        -- math :(
        sgResistance = -nominal/(voltageDiff/givenVoltage - 0.5) - nominal
        sgResistanceDiff = sgResistance - nominal
        stress = sgResistanceDiff/sgResistance*elasticModulus/gaugeFactor
        
        print(i .. ": " .. voltageDiff .. "DV, " .. stress .. " psi, " .. sgResistanceDiff .. " ohms")
        stressString = stressString .. ", " .. stress
      end
      
      file:write(stressString, "\n") -- Write data to file
      --print(stressString) --print to console
      
      
      newData = mbRead(2002, 0)  -- Check status of newData button
    end
  end
  
  -- Close current working file
  file:close()
  setSafeState(1)
end


