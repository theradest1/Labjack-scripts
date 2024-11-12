 -- This code is to record strain gauges to file on labjack
 -- For automatic amplification: Even AIN ports (ie. AIN0) = positive signal, Odd AIN ports (ie. AIN1) = negative signal 
-- Strain Gauges need external amplification - do not connect it to the labjack
-- Tie the strain gauge to ground (from the external amplification) to the labjack ground

-- FILL OUT THESE VARIABLES ACCORDING TO THE STRAIN GAUGES BEING USED
local exciteVolt = 5      -- External voltage used to excite the SGs (usually 10-12 volts)
local nominal = 120 -- 120 or 350 ohms
local elasticModulus = 29000000 -- elastic modulus for arms is 29m
local gaugeFactor = 2.12 --2.12 -- based on the strain gauges
LJ.IntervalConfig(0, .01) --logging interval in ms (.01 is the fastest it can go without just removing the interval timer)

print("Strain Gauge - Log voltage to file")

--disable truncation warnings (remove if you even slightly suspect issues)
MB.writeName("LUA_NO_WARN_TRUNCATION", 1)

-- Check for SD card
if(bit.band(MB.R(60010, 1), 8) ~= 8) then
  print("uSD card not detected")
  stopProgram()
end

-- Initialize local functions (for faster processing)
local mbRead=MB.R
local mbWrite = MB.W
local mbNameToAddress = MB.nameToAddress
local mbReadName = MB.readName
local mbWriteName = MB.writeName
local mbReadArray = MB.RA
local mbWriteArray = MB.WA
local checkInterval=LJ.CheckInterval

-- Initialize variables
local ledState = 1

local givenVoltage = 0
local sgResistance = 0
local sgResistanceDiff = 0
local voltageDiff = 0
local stress = 0

local ainChannel = 0

local logStartTime = 0
local secondsTable = 0

local filename = ""
local timetable = 0

local delimiter = ","
local stressString = ""

-- AIN port config
local ainChannelCorrection = {0, 0, 0, 0, 0}--, 0, 0, 0, 0} --values that zero each channel
local ainChannels = {0, 0, 0, 0, 0}--, 4, 6, 8, 10} -- the channels that are read (only even because the odds are the negative channels)
local givenVoltageChannel = 2
local ainVoltageRange = 0.01 -- +/- 1V input range
local ainResolution = 6 -- 1 is fastest, 12 is most detail (but slowest)
local ainSettlingTime = 0 -- default settling time

-- functions
local function configureChannel(channel, range, resolution, settling, differential)
  --get base addresses
  rangeaddress = mbNameToAddress("AIN0_RANGE")
  resaddress = mbNameToAddress("AIN0_RESOLUTION_INDEX")
  setaddress = mbNameToAddress("AIN0_SETTLING_US")
  negchaddress = mbNameToAddress("AIN0_NEGATIVE_CH")
  
  -- set config
  mbWrite(rangeaddress + channel * 2, 3, range)
  mbWrite(resaddress + channel * 1, 0, resolution)
  --mbWrite(setaddress + channel * 2, 3, settling)
  
  if(differential) then
    mbWrite(negchaddress + channel, 0, channel + 1)
  end
end

local function stopProgram(message)
  message = message or "Script was stopped" -- default message
  print(message) --print message
  
  mbWriteName("FIO1", 1) --set lcd state to off
  mbWriteName("LUA_RUN", 0); -- write 0
  mbWrite(6000, 1, 0); -- stop
end

--loop through strain gauge ain channels
for i=1,table.getn(ainChannels) do
  configureChannel(ainChannels[i], ainVoltageRange, ainResolution, ainSettlingTime, true)
  configureChannel(ainChannels[i] + 1, 10, ainResolution, ainSettlingTime, false) --negative channel
end
configureChannel(givenVoltageChannel, 10, ainResolution, ainSettlingTime, true) --input voltage muesure ain channel


while true do --loop forever
  mbWriteName("FIO1", 0) -- set led
  
  print("\nWaiting for button to be pressed")
  while MB.readName("FIO1") >= 0.5 do
    -- wait for FIO1 to be high (the button)
  end
  
  --get logfile name
  timetable = MB.readNameArray("RTC_TIME_CALENDAR", 6)
  filename = string.format(
    "%04d-%02d-%02d-%02d-%02d-%02d.csv",
    timetable[1], --year
    timetable[2], --month
    timetable[3], --day
    timetable[4], --hour
    timetable[5], --minute
    timetable[6]) --second
  
  -- Create and open file for write access
  local file = io.open(filename, "w")

  -- Make sure that the file was opened properly.
  if file then
    print("\nCreated and opened debug file with name " .. filename .. "\n")
  else
    -- If the file was not opened properly we probably have a bad SD card.
    stopProgram("!! Failed to open file on uSD Card !! \n Stoping script\n")
  end
  
  --create header
  header = "time"
  for i=1,table.getn(ainChannels) do
    header = string.format("%s, strain%d", header, i)
  end
  
  --write header
  file:write(header, "\n")
  print(header)
  
  -- NewData button has been pressed - start recording data
  while mbRead(2002, 0) < 0.5 do
    if checkInterval() then
      ledState = 1 - ledState -- turn on and off
      mbWriteName("FIO1", ledState) -- set led
      
      --get time
      secondsTable = mbReadArray(61500, 0, 2)
      stressString = string.format("%d%d.%04d", secondsTable[1], secondsTable[2], mbRead(61502, 1))
      
      givenVoltage = mbRead(givenVoltageChannel * 2, 3) -- get Vs
      for i=1,table.getn(ainChannels) do
        -- get variable values
        voltageDiff = mbRead(ainChannels[i] * 2, 3) -- get voltage diff
        voltageDiff = voltageDiff + ainChannelCorrection[i] -- correct voltage input
        
        -- math :(
        sgResistance = -nominal/(voltageDiff/givenVoltage - 0.5) - nominal
        sgResistanceDiff = sgResistance - nominal
        stress = sgResistanceDiff/sgResistance*elasticModulus/gaugeFactor
        
        stressString = stressString .. ", " .. stress
      end
      file:write(stressString, "\n") -- Write data to file
      print(stressString) --print to console
      
      --zeroing
      if mbRead(2000, 0) < .5 then
        for i=1, table.getn(ainChannels) do --loop through channels
          ain = mbRead(ainChannels[i] * 2, 3) --get value
          
          ainChannelCorrection[i] = -ain -- set correction to -value
          
          print("zerod")
        end
      end
    end
  end
  
  -- Close current working file
  file:flush() --make sure its saved
  file:close() --close the file
  print("Closed file")
  mbWriteName("FIO1", 0) -- set led
end


