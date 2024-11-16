 -- This code is to record strain gauges to file on labjack
 -- For automatic amplification: Even AIN ports (ie. AIN0) = positive signal, Odd AIN ports (ie. AIN1) = negative signal 
-- Strain Gauges need external amplification - do not connect it to the labjack
-- Tie the strain gauge to ground (from the external amplification) to the labjack ground

-- put an led on FIO1
-- zeroing switch on FIO0 (other side to ground)
-- logging switch on FIO2 (other side to ground)

-- FILL OUT THESE VARIABLES ACCORDING TO THE STRAIN GAUGES BEING USED
local elasticModulus = 29000000 -- elastic modulus for arms is 29m
local gaugeFactor = 2.12 --2.12 -- based on the strain gauges
-- set nominal resistances where below where pins are set

--syncing sin wave
local sinWaveHz = 2
local timeMultSin = 2 * 3.1415 * sinWaveHz --pre calculation

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
local mbWriteName = MB.writeName
local mbReadArray = MB.RA
local checkInterval = LJ.CheckInterval

-- Initialize variables
local ledState = 1

local givenVoltage = 0
local sgResistance = 0
local sgResistanceDiff = 0
local voltageDiff = 0
local stress = 0
local nominalResistance = 0

local filename = ""
local timetable = 0

local writeString = ""
local header = ""

local startTime = 0
local currentTime = 0
local sinWave = 0

-- AIN port config
local ainChannelCorrection = {0, 0, 0, 0, 0}--, 0, 0, 0, 0} --values that zero each channel
local nominalResistances = {120, 350, 120, 120, 120}  -- 120 or 350 ohms
local ainChannels = {0, 2, 4, 6, 8}--, 4, 6, 8, 10} -- the channels that are read (only even because the odds are the negative channels)
local ainChannelNum = table.getn(ainChannels)

local ainChannelAddresses = {} --pre calculation of channel addresses
for i=1,ainChannelNum do
  ainChannelAddresses[i] = ainChannels[i] * 2
end

local givenVoltageChannel = 10
local givenVoltageChannelAddress = givenVoltageChannel * 2 --pre calculation
local ainVoltageRange = 0.01 -- +/- 1V input range
local ainResolution = 8 -- 1 is fastest, 12 is most detail (but slowest)
local ainSettlingTime = 0 -- default settling time

-- functions
local function configureChannel(channel, range, resolution, settling, differential)
  local channel_int = string.format("%d", channel)
  
  -- set config
  mbWriteName("AIN".. channel_int .."_EF_INDEX", 0) -- turn off extended features
  mbWriteName("AIN".. channel_int .."_RANGE", range)
  mbWriteName("AIN".. channel_int .."_RESOLUTION_INDEX", resolution)
  mbWriteName("AIN".. channel_int .."_SETTLING_US", settling)
  
  if(differential) then
    mbWriteName("AIN".. channel_int .."_NEGATIVE_CH", channel + 1) --set negative channel
  else
    mbWriteName("AIN".. channel_int .."_NEGATIVE_CH", 199) --turn off negative channel
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
for i=1,ainChannelNum do
  configureChannel(ainChannels[i], ainVoltageRange, ainResolution, ainSettlingTime, true)
  configureChannel(ainChannels[i] + 1, 10, ainResolution, ainSettlingTime, false) --negative channel
end
configureChannel(givenVoltageChannel, 10, ainResolution, ainSettlingTime, false) --input voltage muesure ain channel


while true do --loop forever
  mbWriteName("FIO1", 0) -- set led
  
  print("\nWaiting for button to be pressed")
  while MB.readName("FIO2") >= 0.5 do -- wait for FIO2 to be zero
    --zeroing
    if MB.readName("FIO0") < .5 then
      mbWrite(2001, 0, 1) -- set led
      
      for i=1, ainChannelNum do --loop through channels
        
        voltageDiff = mbRead(ainChannelAddresses[i], 3) --get value
        
        ainChannelCorrection[i] = -voltageDiff -- set correction to -value
      end
    end
    mbWrite(2001, 0, 0) -- set led
  end
  ledState = 0
  
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
    print("\nCreated and opened log file with name " .. filename .. "\n")
  else
    -- If the file was not opened properly we probably have a bad SD card.
    stopProgram("!! Failed to open file on uSD Card !! \n Stoping script\n")
  end
  
  --create header
  header = "sinWave, time, inputVoltage"
  for i=1,ainChannelNum do
    header = string.format("%s, voltage%d", header, i)
  end
  
  --write header
  file:write(header, "\n")
  --print(header)
  
  startTime = mbReadArray(61500, 0, 2)[2] + mbRead(61502, 1)/10000
  
  -- NewData button has been pressed - start recording data
  
  while mbRead(2002, 0) < 0.5 do
    ledState = 1 - ledState -- turn on and off
    mbWrite(2001, 0, ledState) -- set led
    
    --get time
    currentTime = mbReadArray(61500, 0, 2)[2] + mbRead(61502, 1)/10000 - startTime
    if currentTime < 0 then
      currentTime = currentTime + 65536 --keep it from going negative from start time offset
    end
    
    --input voltage
    givenVoltage = mbRead(givenVoltageChannelAddress, 3)
    
    --sin wave
    sinWave = math.sin(currentTime * timeMultSin)
    
    --collect
    writeString = sinWave .. ", " .. currentTime .. ", " .. givenVoltage
    
    --output sin wave to DAC0
    mbWrite(1000, 3, 2.5 * sinWave + 2.5) -- 0V to 5V
    
    --go through channels
    for i=1,ainChannelNum do
      
      -- get variable values
      voltageDiff = mbRead(ainChannelAddresses[i], 3) -- get voltage diff
      voltageDiff = voltageDiff + ainChannelCorrection[i] -- correct voltage input
      
      --get nominal resistance
      --nominalResistance = nominalResistances[i]
      
      -- math :(
      --sgResistance = nominalResistance/(1/(voltageDiff/givenVoltage + 0.5)-1)
      --sgResistanceDiff = sgResistance - nominalResistance
      --stress = sgResistanceDiff/sgResistance*elasticModulus/gaugeFactor
      
      writeString = writeString .. ", " .. voltageDiff -- make negative if stress
    end
    file:write(writeString, "\n") -- Write data to file
    print(writeString) --print to console
    
    if MB.readName("FIO0") < .5 then
      mbWrite(2001, 0, 1) -- set led
      
      for i=1, ainChannelNum do --loop through channels
        
        voltageDiff = mbRead(ainChannelAddresses[i], 3) --get value
        
        ainChannelCorrection[i] = -voltageDiff -- set correction to -value
      end
    end
  end
  
  -- Close current working file
  file:flush() --make sure its saved
  file:close() --close the file
  
  print("Closed file")
  mbWriteName("FIO1", 0) -- set led
end


