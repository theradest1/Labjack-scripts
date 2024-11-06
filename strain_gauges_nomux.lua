 -- This code is to record strain gauges to file on labjack
 -- For automatic amplification: Even AIN ports (ie. AIN0) = positive signal, Odd AIN ports (ie. AIN1) = negative signal 
-- Strain Gauges need external amplification - do not connect it to the labjack
-- Tie the strain gauge to ground (from the external amplification) to the labjack ground

-- FILL OUT THESE VARIABLES ACCORDING TO THE STRAIN GAUGES BEING USED
local exciteVolt = 5      -- External voltage used to excite the SGs (usually 10-12 volts)
local nominal = 120 -- 120 or 350 ohms
local elasticModulus = 29000000 --elastic modulus for arms is 29m
local gaugeFactor = 2.12 -- based on the strain gauges
local logInterval = 250 --in ms

print("Strain Gauge - Log voltage to file")


local function configureChannel(channel, range, resolution, settling)
  --get base addresses
  local rangeAddress = MB.nameToAddress("AIN0_RANGE")
  local rasolutionAddress = MB.nameToAddress("AIN0_RESOLUTION_INDEX")
  local settlingAddress = MB.nameToAddress("AIN0_SETTLING_US")
  local negativeAddress = MB.nameToAddress("AIN0_NEGATIVE_CH")
  
  MB.W(rangeAddress + channel * 2, 3, range) -- set the range
  MB.W(rasolutionAddress + channel * 1, 0, resolution) -- set resolution
  MB.W(settlingAddress + channel * 2, 3, settling) --set settling time
  MB.W(negativeAddress + channel, 0, channel + 1) --set the channel's negative address
end


-- Check for SD card
if(bit.band(MB.R(60010, 1), 8) ~= 8) then
  print("uSD card not detected")
  stopProgram()
end

-- Initialize local functions (for faster processing)
local mbRead=MB.R
local mbWrite = MB.W
local mbWriteName = MB.writeName
local checkInterval=LJ.CheckInterval
local setInterval = LJ.IntervalConfig

-- Initialize variables
local waitingInterval = 250 --how much time between checks of when loggin should start
local safeState = 1 -- 1 if file isn't being written to
local ledState = 1

local newData = 1
local givenVoltage = 0 -- found in loop

local zeroAin = 0

local sgResistance = 0
local sgResistanceDiff = 0
local voltageDiff = 0
local strain = 0
local ainChannel = 0

local delimiter = ","
local strainList = {}
local strainString = ""

-- Configure AIN ports
local ainChannelCorrection = {0, 0, 0, 0, 0} --values that zero each channel
local ainChannels = {0, 2, 4, 6, 8} -- the channels that are read (only even because the odds are the negative channels)
local givenVoltageChannel = 10
local ainVoltageRange = 1 -- +/- 1V input range
local ainResolution = 1 -- 1 is fastest setting?
local ainSettlingTime = 0 -- default settling time

--loop through strain gauge ain channels
for i=1,table.getn(ainChannels) do
  ainChannel = ainChannels[i] --get ainChannel
  configureChannel(ainChannel, ainVoltageRange, ainResolution, ainSettingTime)
end

configureChannel(givenVoltageChannel, 10, 1, 0) --input voltage muesure ain channel


-- functions
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
  
  MB.writeName("FIO1", 1) --set lcd state to off
  MB.writeName("LUA_RUN", 0); -- write 0
  MB.W(6000, 1, 0); -- stop
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
  setInterval(0, 50) --make it loop fast
  setSafeState(0)
  
  print("\nzeroing channels")
  while zeroAin < 0.5 do
    if checkInterval() then
      updateDebugLED()
      
      for i=1,table.getn(ainChannels) do --loop through channels
        ain = mbRead(ainChannels[i], 3) --get value
        
        ainChannelCorrection[i] = -ain -- set correction to -value
      end
      
      zeroAin = mbRead(2000, 0) --FIO0
    end
  end
  
  setSafeState(1)
  print("\nChannel correction:\n", table.concat(ainChannelCorrection, delimiter))
end


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
  print("Loging data:\n")
  
  csvHeader = "sg1, sg2, sg3, sg4, sg5"
  file:write(csvHeader, "\n") -- Write data to file
  print(csvHeader)
  
  -- Set logging interval
  setInterval(0, logInterval)
  
  -- NewData button has been pressed - start recording data
  while newData < 0.5 do
    if checkInterval() then
      updateDebugLED()
      
      strainList = {} -- clear list
      
      for i=1,table.getn(ainChannels) do
        -- get variable values
        givenVoltage = mbRead(givenVoltageChannel, 3) -- get Vs
        voltageDiff = mbRead(ainChannels[i], 3) + ainChannelCorrection[i] --get voltage difference, and correct
        
        if(math.abs(voltageDiff) > ainVoltageRange) then
          stopProgram("Voltage range is too small")
        end
        
        -- math :(
        sgResistance = -nominal/(voltageDiff/givenVoltage - .5) - nominal
        sgResistanceDiff = sgResistance - nominal
        strain = sgResistanceDiff/sgResistance*elasticModulus/gaugeFactor
        
        table.insert(strainList, tostring(strain))
      end
      strainString = table.concat(strainList, delimiter) -- convert to string
      
      file:write(strainString, "\n") -- Write data to file
      print(strainString) --print to console
      
      newData = mbRead(2002, 0)  -- Check status of newData button
    end
  end
  
  -- Close current working file
  file:close()
  safeState = 1
end


