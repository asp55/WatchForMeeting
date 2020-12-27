--- === WatchForMeeting ===
---
--- A module that monitors whether or not you're in a meeting, and updates a self served webpage

local obj={}
obj.__index = obj

-- Metadata
obj.name = "WatchForMeeting"
obj.version = "0.1"
obj.author = "Andrew Parnell <aparnell@gmail.com>"
obj.homepage = "https://github.com/asp55/WatchForMeeting"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- WatchForMeeting.logger
--- Variable
--- Logger object used within the Spoon. Can be accessed to set the default log level for the messages coming from the Spoon.
obj.logger = hs.logger.new('WatchMeeting')

-------------------------------------------
-- Declare Variables
-------------------------------------------

obj.port = 12345
obj.meetingState = false
obj.zoom = nil

-------------------------------------------
--End of Declare Variables
-------------------------------------------

-------------------------------------------
-- Web Server
-------------------------------------------
local server = hs.httpserver.new()

local function panelJSON() 
   local message = {type="update", inZoom=obj.meetingState}
   return hs.json.encode(message)
end

local monitorfile = io.open(hs.spoons.resourcePath("monitor.html"), "r")
local htmlContent = monitorfile:read("*a")
monitorfile:close()

local function httpCallback()
   local websocketPath = "ws://"..hs.network.interfaceDetails(hs.network.primaryInterfaces())["IPv4"]["Addresses"][1]..":"..obj.port.."/ws"
   htmlContent = string.gsub(htmlContent,"%%websocketpath%%",websocketPath)
   return htmlContent, 200, {}
end

local function websocketCallback(msg)
   if(msg == "Connected") then
      obj.logger.d("Client connected: ",msg)
      return panelJSON()
   elseif(string.sub(msg, 0, 7) == "Update:") then
      obj.logger.d("Update: ", string.sub(msg,7))
   else
      obj.logger.d("Message received: ",msg)
      return "Received "..msg
   end
end

-------------------------------------------
-- End Web Server
-------------------------------------------

-------------------------------------------
-- Zoom Monitor
-------------------------------------------

local function checkInMeeting()
   return (obj.zoom ~= nil and obj.zoom:getMenuItems()[2].AXTitle == "Meeting")
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
      local _mic_open = obj.zoom:findMenuItem({"Meeting", "Unmute Audio"})==nil
      local _video_on = obj.zoom:findMenuItem({"Meeting", "Start Video"})==nil
      local _sharing = obj.zoom:findMenuItem({"Meeting", "Start Share"})==nil
      if((obj.meetingState.mic_open ~= _mic_open) or (obj.meetingState.video_on ~= _video_on) or (obj.meetingState.sharing ~= _sharing)) then
         obj.meetingState = {mic_open = _mic_open, video_on = _video_on, sharing = _sharing}
         obj.logger.d("In Meeting: ", (obj.meetingState and true)," Open Mic: ",obj.meetingState.mic_open," Video-ing:",obj.meetingState.video_on," Sharing",obj.meetingState.sharing)
         server:send(panelJSON())
      end
   end
end)

startStopWatchMeeting = function()
   if(obj.meetingState == false and checkInMeeting() == true) then
      obj.logger.d("Start Meeting")
         obj.meetingState = {}
         watchMeeting:start()
         watchMeeting:fire()
   elseif(obj.meetingState and checkInMeeting() == false) then
      obj.logger.d("End Meeting")
      watchMeeting:stop()
      obj.meetingState = false
      server:send(panelJSON())
   end
end

local function checkMeetingStatus(window, name, event)
	obj.logger.d("Check Meeting Status",window,name,event)
   obj.zoom = window:application() --hs.application.find("zoom.us")
   
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

function obj:start()
   server:websocket("/ws", websocketCallback)
   server:setPort(self.port)
   server:setCallback(httpCallback)
   server:start()
   zoomWindowFilter:resume()
   return self
end

function obj:stop()
   server:stop()
   zoomWindowFilter:pause()
end

return obj
