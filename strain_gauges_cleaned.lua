local elasticModulus = 29000000 
local gaugeFactor = 2.12 
LJ.IntervalConfig(0, .01) 
local sinWaveHz = .1
MB.writeName("LUA_NO_WARN_TRUNCATION", 1)
if(bit.band(MB.R(60010, 1), 8) ~= 8) then
  stopProgram()
end
local mbRead=MB.R
local mbWrite = MB.W
local mbWriteName = MB.writeName
local mbReadArray = MB.RA
local checkInterval = LJ.CheckInterval
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
local ainChannelCorrection = {0, 0, 0, 0, 0}
local nominalResistances = {120, 350, 120, 120, 120}  
local ainChannels = {0, 2, 4, 6, 8}
local ainChannelNum = table.getn(ainChannels)
local givenVoltageChannel = 10
local ainVoltageRange = 0.01 
local ainResolution = 8 
local ainSettlingTime = 0 
local function configureChannel(channel, range, resolution, settling, differential)
  local channel_int = string.format("%d", channel)
  mbWriteName("AIN".. channel_int .."_RANGE", range)
  mbWriteName("AIN".. channel_int .."_RESOLUTION_INDEX", resolution)
  mbWriteName("AIN".. channel_int .."_EF_INDEX", 0) 
  mbWriteName("AIN".. channel_int .."_SETTLING_US", settling)
  if(differential) then
    mbWriteName("AIN".. channel_int .."_NEGATIVE_CH", channel + 1) 
  else
    mbWriteName("AIN".. channel_int .."_NEGATIVE_CH", 199) 
  end
end
local function stopProgram(message)
  message = message or "Script was stopped" 
  mbWriteName("FIO1", 1) 
  mbWriteName("LUA_RUN", 0); 
  mbWrite(6000, 1, 0); 
end
for i=1,ainChannelNum do
  configureChannel(ainChannels[i], ainVoltageRange, ainResolution, ainSettlingTime, true)
  configureChannel(ainChannels[i] + 1, 10, ainResolution, ainSettlingTime, false) 
end
configureChannel(givenVoltageChannel, 10, ainResolution, ainSettlingTime, false) 
while true do 
  mbWriteName("FIO1", 0) 
  while MB.readName("FIO2") >= 0.5 do
  end
  timetable = MB.readNameArray("RTC_TIME_CALENDAR", 6)
  filename = string.format(
    "%04d-%02d-%02d-%02d-%02d-%02d.csv",
    timetable[1], 
    timetable[2], 
    timetable[3], 
    timetable[4], 
    timetable[5], 
    timetable[6]) 
  local file = io.open(filename, "w")
  if file then
  else
    stopProgram("!! Failed to open file on uSD Card !! \n Stoping script\n")
  end
  header = "sinWave, time, inputVoltage"
  for i=1,ainChannelNum do
    header = string.format("%s, voltage%d", header, i)
  end
  file:write(header, "\n")
  startTime = mbReadArray(61500, 0, 2)[2] + mbRead(61502, 1)/10000
  while mbRead(2002, 0) < 0.5 do
    if checkInterval() then
      ledState = 1 - ledState 
      mbWriteName("FIO1", ledState) 
      currentTime = mbReadArray(61500, 0, 2)[2] + mbRead(61502, 1)/10000 - startTime
      if currentTime < 0 then
        currentTime = currentTime + 65536 
      end
      givenVoltage = mbRead(givenVoltageChannel * 2, 3)
      sinWave = math.sin(2 * 3.1415 * currentTime * sinWaveHz)
      writeString = sinWave .. ", " .. currentTime .. ", " .. givenVoltage
      mbWrite(1000, 3, 2.5 * sinWave + 2.5) 
      for i=1,ainChannelNum do
        voltageDiff = mbRead(ainChannels[i] * 2, 3) 
        voltageDiff = voltageDiff + ainChannelCorrection[i] 
        nominalResistance = nominalResistances[i]
        sgResistance = nominalResistance/(1/(voltageDiff/givenVoltage + 0.5)-1)
        sgResistanceDiff = sgResistance - nominalResistance
        stress = sgResistanceDiff/sgResistance*elasticModulus/gaugeFactor
        writeString = writeString .. ", " .. stress
      end
      file:write(writeString, "\n") 
      if mbRead(2000, 0) < .5 then
        for i=1, ainChannelNum do 
          voltageDiff = mbRead(ainChannels[i] * 2, 3) 
          ainChannelCorrection[i] = -voltageDiff 
        end
      end
    end
  end
  file:flush() 
  file:close() 
  mbWriteName("FIO1", 0) 
end
