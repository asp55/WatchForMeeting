--- === WatchForMeeting ===
---
--- A module that monitors whether or not you're in a meeting

-- create a namespace

local WatchForMeeting={}
WatchForMeeting.__index = WatchForMeeting

-- Metadata
WatchForMeeting.name = "WatchForMeeting"
WatchForMeeting.version = "0.1"
WatchForMeeting.author = "Andrew Parnell <aparnell@gmail.com>"
WatchForMeeting.homepage = "https://github.com/asp55/WatchForMeeting"
WatchForMeeting.license = "MIT - https://opensource.org/licenses/MIT"

--- WatchForMeeting.logger
--- Variable
--- Logger object used within the Spoon. Can be accessed to set the default log level for the messages coming from the Spoon.
WatchForMeeting.logger = hs.logger.new('WatchMeeting')

-------------------------------------------
-- Declare Variables
-------------------------------------------


WatchForMeeting.sharing = {
   selfHost=true,
   port=12345
}

WatchForMeeting.running = false
--Configuration Variables
WatchForMeeting.room = hs.host.localizedName()
WatchForMeeting.waitBeforeRetry = 0.5
WatchForMeeting.maxConnectionAttempts = 3

WatchForMeeting.meetingState = false
WatchForMeeting.zoom = nil

-------------------------------------------
-- End of Declare Variables
-------------------------------------------


-------------------------------------------
-- Web Server
-------------------------------------------
local server = nil

local function panelJSON() 
   local message = {action="update", inMeeting=WatchForMeeting.meetingState}
   return hs.json.encode(message)
end

local monitorfile = io.open(hs.spoons.resourcePath("monitor.html"), "r")
local htmlContent = monitorfile:read("*a")
monitorfile:close()

local function httpCallback()
   local websocketPath = "ws://"..hs.network.interfaceDetails(hs.network.primaryInterfaces())["IPv4"]["Addresses"][1]..":"..WatchForMeeting.sharing.port.."/ws"
   htmlContent = string.gsub(htmlContent,"%%websocketpath%%",websocketPath)
   return htmlContent, 200, {}
end

local function websocketCallback(msg)
   return panelJSON()
end
-------------------------------------------
-- End Web Server
-------------------------------------------

-------------------------------------------
-- Zoom Monitor
-------------------------------------------

local function checkInMeeting()
   return (WatchForMeeting.zoom ~= nil and WatchForMeeting.zoom:getMenuItems()[2].AXTitle == "Meeting")
end

--declare startStopWatchMeeting before watchMeeting, define it after.
local startStopWatchMeeting = function() end

local watchMeeting = hs.timer.new(0.5, function()
   -- If the second menu isn't called "Meeting" then zoom is no longer in a meeting
    if(checkInMeeting() == false) then
      -- No longer in a meeting, stop watching the meeting
      startStopWatchMeeting()
      return
    else 
      --Watch for zoom menu items
      local _mic_open = WatchForMeeting.zoom:findMenuItem({"Meeting", "Unmute Audio"})==nil
      local _video_on = WatchForMeeting.zoom:findMenuItem({"Meeting", "Start Video"})==nil
      local _sharing = WatchForMeeting.zoom:findMenuItem({"Meeting", "Start Share"})==nil
      if((WatchForMeeting.meetingState.mic_open ~= _mic_open) or (WatchForMeeting.meetingState.video_on ~= _video_on) or (WatchForMeeting.meetingState.sharing ~= _sharing)) then
         WatchForMeeting.meetingState = {mic_open = _mic_open, video_on = _video_on, sharing = _sharing}
         WatchForMeeting.logger.d("In Meeting: ", (WatchForMeeting.meetingState and true)," Open Mic: ",WatchForMeeting.meetingState.mic_open," Video-ing:",WatchForMeeting.meetingState.video_on," Sharing",WatchForMeeting.meetingState.sharing)
         if(server) then server:send(panelJSON()) end
      end
   end
end)

startStopWatchMeeting = function()
   if(WatchForMeeting.meetingState == false and checkInMeeting() == true) then
      WatchForMeeting.logger.d("Start Meeting")
         WatchForMeeting.meetingState = {}
         watchMeeting:start()
         watchMeeting:fire()
   elseif(WatchForMeeting.meetingState and checkInMeeting() == false) then
      WatchForMeeting.logger.d("End Meeting")
      watchMeeting:stop()
      WatchForMeeting.meetingState = false
      if(server) then server:send(panelJSON()) end
   end
end

local function checkMeetingStatus(window, name, event)
	WatchForMeeting.logger.d("Check Meeting Status",window,name,event)
   WatchForMeeting.zoom = window:application() --hs.application.find("zoom.us")
   
   startStopWatchMeeting()

end

-- Monitor zoom for running meeting
hs.application.enableSpotlightForNameSearches(true)
local zoomWindowFilter = hs.window.filter.new(false,"ZoomWindowFilterLog",0):setAppFilter('zoom.us')
zoomWindowFilter:subscribe(hs.window.filter.hasWindow,checkMeetingStatus,true)
zoomWindowFilter:subscribe(hs.window.filter.hasNoWindows,checkMeetingStatus)
zoomWindowFilter:subscribe(hs.window.filter.windowDestroyed,checkMeetingStatus)
zoomWindowFilter:subscribe(hs.window.filter.windowTitleChanged,checkMeetingStatus)
zoomWindowFilter:pause() 

-------------------------------------------
-- End of Zoom Monitor
-------------------------------------------


local _connectionAttempts = 0
local _connectionError = false


--Declare function before start connection because they're circular
local function retryConnection()
end
local function stopConnection()
   if(server) then
      if(getmetatable(server).stop) then server:stop() end
      if(getmetatable(server).close) then server:close() end
   end
end

local function localWebsocketCallback(type, message)
   if(type=="open") then
      _connectionAttempts = 0

      local draft = {action="identify", key=WatchForMeeting.sharing.key, name=WatchForMeeting.room, type="room", status={inMeeting=WatchForMeeting.meetingState}} 
      server:send(hs.json.encode(draft))
   elseif(type == "closed" and WatchForMeeting.running) then
      if(_connectionError) then
         WatchForMeeting.logger.d("Lost connection to websocket, will not reattempt due to error")
      else
         WatchForMeeting.logger.d("Lost connection to websocket, attempting to reconnect in "..WatchForMeeting.waitBeforeRetry.." seconds")
         retryConnection()
      end
   elseif(type == "fail") then
      WatchForMeeting.logger.d("Could not connect to websocket server. attempting to reconnect in "..WatchForMeeting.waitBeforeRetry.." seconds. (Attempt ".._connectionAttempts.."/"..WatchForMeeting.maxConnectionAttempts..")")
      retryConnection()
   elseif(type == "received") then
      local parsed = hs.json.decode(message);
      if(parsed.error) then
         _connectionError = true;
         if(parsed.errorType == "badkey") then
            stopConnection()
            hs.showError("")
            WatchForMeeting.logger.e("sharing.key not valid")
         end
      else
         WatchForMeeting.logger.d("Websocket Message received: ", hs.inspect.inspect(parsed));
      end

   else
      WatchForMeeting.logger.d("Websocket Callback "..type, message) 
   end
end


local function startConnection() 
   if(WatchForMeeting.sharing) then
      if(WatchForMeeting.sharing.useServer) then
         _connectionAttempts = _connectionAttempts + 1
         server = hs.websocket.new(WatchForMeeting.sharing.url, localWebsocketCallback);
      else
         server = hs.httpserver.new()
         server:websocket("/ws", websocketCallback)
         server:setPort(WatchForMeeting.sharing.port)
         server:setCallback(httpCallback)
         server:start()
      end
   end
end

retryConnection = function()
   if(_connectionAttempts >= WatchForMeeting.maxConnectionAttempts) then 
      WatchForMeeting.logger.e("Maximum Connection Attempts failed")
      stopConnection()
   elseif(_connectionError) then
      stopConnection()
   else
      hs.timer.doAfter(WatchForMeeting.waitBeforeRetry, startConnection) 
   end
end


local function validateShareSettings(settings)
   if(settings) then
      if(settings.useServer and (settings.url==nil or settings.key==nil)) then
         hs.showError("")
         if(settings.url==nil) then WatchForMeeting.logger.e("sharing.url required when using a server") end
         if(settings.key==nil) then WatchForMeeting.logger.e("sharing.key required when using a server") end
         return false
      elseif(not settings.useServer and settings.port==nil) then
         hs.showError("")
         WatchForMeeting.logger.e("sharing.port required when self hosting")
         return false
      else
         return true
      end
   end
   return false
end


function WatchForMeeting:start()
   if(not self.running) then
      self.running = true
      if(validateShareSettings(self.sharing)) then
         startConnection()
      end
      zoomWindowFilter:resume()
   else
      hs.showError("")
      WatchForMeeting.logger.e("Cannot start, already running.")
   end
   return self
end

function WatchForMeeting:stop()
   self.running = false
   stopConnection()
   zoomWindowFilter:pause()
   return self
end

return WatchForMeeting
