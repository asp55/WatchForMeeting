--- === WatchForMeeting ===
---
--- A module that monitors whether or not you are in a meeting and optionally shares that information on a webpage you can run elsewhere.


--We'll store some stuff in an internal table

local _internal = {}

-- create a namespace

local WatchForMeeting={}
WatchForMeeting.__index = WatchForMeeting


-- Metadata
WatchForMeeting.name = "WatchForMeeting"
WatchForMeeting.version = "1.0"
WatchForMeeting.author = "Andrew Parnell <aparnell@gmail.com>"
WatchForMeeting.homepage = "https://github.com/asp55/WatchForMeeting"
WatchForMeeting.license = "MIT - https://opensource.org/licenses/MIT"



-------------------------------------------
-- Declare Variables
-------------------------------------------


--- WatchForMeeting.logger
--- Variable
--- Logger object used within the Spoon. Can be accessed to set the default log level for the messages coming from the Spoon.
WatchForMeeting.logger = hs.logger.new('WatchMeeting')

--- WatchForMeeting.sharing
--- Variable
--- Settings that control sharing.
---
--- - enabled
--- -- Whether or not sharing is enabled. True by default. When disabled, the spoon will still monitor meeting status, but you will need to write your own automations for what to do with that info. 
--- - useServer
--- -- *true* - (recommended) an external server will store the meeting status and provide the web interface for monitoring meeting status. (Node.js sample server can be found at [https://github.com/asp55/MeetingStatusServer](https://github.com/asp55/MeetingStatusServer))
--- -- *false* - hammerspoon will self serve the monitoring page. (Due to a limitation in hs.httpserver:websocket the monitoring page will only update in the last client to connect.) 
--- - port
--- -- What port to run the self hosted server when WatchForMeeting.sharing.useServer is false. (Defaults to 8080)
--- -- Ignored if WatchForMeeting.sharing.useServer is true.
--- - serverURL
--- -- The complete url for the external server. (including port)
--- -- Required when WatchForMeeting.sharing.useServer is *true*
--- - key
--- -- UUID to identify the room. Value is provided when the room is added on the server side. 
--- -- Required when WatchForMeeting.sharing.useServer is *true*
--- - maxConnectionAttempts
--- -- Maximum number of connection attempts when using an external server.
--- - waitBeforeRetry
--- -- Time, in seconds, between connection attempts when using an external server

WatchForMeeting.sharing = {}
WatchForMeeting.sharing.enabled = true
WatchForMeeting.sharing.useServer = false
WatchForMeeting.sharing.port = 8080
WatchForMeeting.sharing.serverURL = nil
WatchForMeeting.sharing.key = nil
WatchForMeeting.sharing.maxConnectionAttempts = -1 --when less than 0, infinite retrys
WatchForMeeting.sharing.waitBeforeRetry = 5



-- private variable to track if spoon is already running or not. (Makes it easier to find local variables)
_internal.running = false

   -------------------------------------------
   -- Special Variables (stored in _internal and accessed through metamethods defined below)
   -------------------------------------------

   --- WatchForMeeting.menubar
   --- Variable
   --- Boolean whether or not to show the menubar item
   _internal.menubar = true

   --- WatchForMeeting.mode
   --- Variable
   --- Number representing which mode WatchForMeeting should be running
   ---
   --- - *0* - Automatic (default)
   --- -- Monitors Zoom and updates status accordingly
   --- - *1* - Busy
   --- -- Fakes a meeting. (Marks as in meeting, and signals that the mic is live, camera is on, and screen is sharing.) Useful when meeting type is not supported (Currently any platform that isn't zoom.)
   _internal.mode = 0

   --- WatchForMeeting.zoom
   --- Variable
   --- (Read-only) The hs.application for zoom if it is running, otherwise nil
   _internal.zoom = nil

   --- WatchForMeeting.meetingState
   --- Variable
   --- (Read-only) Either false (when not in a meeting) or a table (when in a meeting)
   ---
   --- When in a meeting, table will have the following keys with boolean values:
   --- - mic_open 
   --- - video_on 
   --- - sharing 
   _internal.meetingState = false

   -- MetaMethods
   WatchForMeeting = setmetatable(WatchForMeeting, {
      __index = function (table, key)
         if(key=="zoom" or key=="meetingState" or key=="menubar" or key=="mode") then
            return _internal[key]
         else
            return rawget( table, key )
         end
      end,
      __newindex = function (table, key, value)
         if(key=="zoom" or key=="meetingState") then
            --skip writing zoom or meeting state to watchformeeting
         elseif(key=="menubar") then
            if(value) then 
               _internal.meetingMenuBar:returnToMenuBar()
               _internal.updateMenuIcon(_internal.faking or _internal.meetingState)
            else
               _internal.meetingMenuBar:removeFromMenuBar()
            end
            _internal[key] = value
         elseif(key=="mode") then
            if(value == 1) then 
               table:fake()
            else 
               table:auto() 
            end
         else
            return rawset(table, key, value)
         end
      end
   })

-------------------------------------------
-- End of Declare Variables
-------------------------------------------

-------------------------------------------
-- Menu Bar
-------------------------------------------

_internal.meetingMenuBar = hs.menubar.new(false)


function _internal.updateMenuIcon(status)

   local iconPath = hs.spoons.scriptPath()..'menubar-icons/'

   if(status) then 
      _internal.meetingMenuBar:setIcon(iconPath.."Meeting.pdf",false)
   else
      _internal.meetingMenuBar:setIcon(iconPath.."Free.pdf",false)
   end
end

-------------------------------------------
-- End of Menu Bar
-------------------------------------------


-------------------------------------------
-- Web Server
-------------------------------------------
_internal.server = nil 
_internal.websocketStatus = "closed"

local function composeJsonUpdate(meetingState) 
   local message = {action="update", inMeeting=meetingState}
   return hs.json.encode(message)
end

local monitorfile = io.open(hs.spoons.resourcePath("monitor.html"), "r")
local htmlContent = monitorfile:read("*a")
monitorfile:close()

local function selfhostHttpCallback()
   local websocketPath = "ws://"..hs.network.interfaceDetails(hs.network.primaryInterfaces())["IPv4"]["Addresses"][1]..":"..WatchForMeeting.sharing.port.."/ws"
   htmlContent = string.gsub(htmlContent,"%%websocketpath%%",websocketPath)
   return htmlContent, 200, {}
end

local function selfhostWebsocketCallback(msg)
   return composeJsonUpdate(_internal.meetingState)
end
-------------------------------------------
-- End Web Server
-------------------------------------------

-------------------------------------------
-- Zoom Monitor
-------------------------------------------

local function currentlyInMeeting()
   local inMeetingState = (_internal.zoom ~= nil and _internal.zoom:getMenuItems()[2].AXTitle == "Meeting")
   return inMeetingState
end

--declare startStopWatchMeeting before watchMeeting, define it after.
local startStopWatchMeeting = function() end

local watchMeeting = hs.timer.new(0.5, function()

   -- If the second menu isn't called "Meeting" then zoom is no longer in a meeting
    if(currentlyInMeeting() == false) then
      _internal.updateMenuIcon(false)
      -- No longer in a meeting, stop watching the meeting
      startStopWatchMeeting()
      
      if(_internal.server and _internal.websocketStatus == "open") then _internal.server:send(composeJsonUpdate(_internal.meetingState)) end
      return
    else 
      _internal.updateMenuIcon(true)
      --Watch for zoom menu items
      local _mic_open = _internal.zoom:findMenuItem({"Meeting", "Unmute Audio"})==nil
      local _video_on = _internal.zoom:findMenuItem({"Meeting", "Start Video"})==nil
      local _sharing = _internal.zoom:findMenuItem({"Meeting", "Start Share"})==nil
      if((_internal.meetingState.mic_open ~= _mic_open) or (_internal.meetingState.video_on ~= _video_on) or (_internal.meetingState.sharing ~= _sharing)) then
         _internal.meetingState = {mic_open = _mic_open, video_on = _video_on, sharing = _sharing}
         WatchForMeeting.logger.d("In Meeting: ", (_internal.meetingState and true)," Open Mic: ",_internal.meetingState.mic_open," Video-ing:",_internal.meetingState.video_on," Sharing",_internal.meetingState.sharing)
         if(_internal.server and _internal.websocketStatus == "open") then _internal.server:send(composeJsonUpdate(_internal.meetingState)) end
      end
   end
end)

startStopWatchMeeting = function()
   if(_internal.meetingState == false and currentlyInMeeting() == true) then
      _internal.updateMenuIcon(true)
      WatchForMeeting.logger.d("Start Meeting")
         _internal.meetingState = {}
         watchMeeting:start()
         watchMeeting:fire()
   elseif(_internal.meetingState and currentlyInMeeting() == false) then
      _internal.updateMenuIcon(false)
      WatchForMeeting.logger.d("End Meeting")
      watchMeeting:stop()
      _internal.meetingState = false
      if(_internal.server and _internal.websocketStatus == "open") then _internal.server:send(composeJsonUpdate(_internal.meetingState)) end
   end
end


local function checkMeetingStatus(window, name, event)
	WatchForMeeting.logger.d("Check Meeting Status",window,name,event)
   _internal.zoom = window:application()   
   startStopWatchMeeting()
end

-- Monitor zoom for running meeting
hs.application.enableSpotlightForNameSearches(true)
_internal.zoomWindowFilter = hs.window.filter.new(false,"ZoomWindowFilterLog",0):setAppFilter('zoom.us')
_internal.zoomWindowFilter:subscribe(hs.window.filter.hasWindow,checkMeetingStatus,true)
_internal.zoomWindowFilter:subscribe(hs.window.filter.hasNoWindows,checkMeetingStatus)
_internal.zoomWindowFilter:subscribe(hs.window.filter.windowDestroyed,checkMeetingStatus)
_internal.zoomWindowFilter:subscribe(hs.window.filter.windowTitleChanged,checkMeetingStatus)
_internal.zoomWindowFilter:pause() 

-------------------------------------------
-- End of Zoom Monitor
-------------------------------------------


_internal.connectionAttempts = 0
_internal.connectionError = false


--Declare function before start connection because they're circular
local function retryConnection()
end
local function stopConnection()
   if(_internal.server) then
      if(getmetatable(_internal.server).stop) then _internal.server:stop() end
      if(getmetatable(_internal.server).close) then _internal.server:close() end
   end
end

local function serverWebsocketCallback(type, message)
   if(type=="open") then
      _internal.websocketStatus = "open"
      _internal.connectionAttempts = 0

      local draft = {action="identify", key=WatchForMeeting.sharing.key, type="room", status={inMeeting=_internal.meetingState}} 
      _internal.server:send(hs.json.encode(draft))
   elseif(type == "closed" and _internal.running) then
      _internal.websocketStatus = "closed"
      if(_internal.connectionError) then
         WatchForMeeting.logger.d("Lost connection to websocket, will not reattempt due to error")
      else
         WatchForMeeting.logger.d("Lost connection to websocket, attempting to reconnect in "..WatchForMeeting.sharing.waitBeforeRetry.." seconds")
         retryConnection()
      end
   elseif(type == "fail") then
      _internal.websocketStatus = "fail"
      if(WatchForMeeting.sharing.maxConnectionAttempts > 0) then
         WatchForMeeting.logger.d("Could not connect to websocket server. attempting to reconnect in "..WatchForMeeting.sharing.waitBeforeRetry.." seconds. (Attempt ".._internal.connectionAttempts.."/"..WatchForMeeting.sharing.maxConnectionAttempts..")")
      else
         WatchForMeeting.logger.d("Could not connect to websocket server. attempting to reconnect in "..WatchForMeeting.sharing.waitBeforeRetry.." seconds. (Attempt ".._internal.connectionAttempts..")")
      end
      retryConnection()
   elseif(type == "received") then
      local parsed = hs.json.decode(message);
      if(parsed.error) then
         _internal.connectionError = true;
         if(parsed.errorType == "badkey") then
            stopConnection()
            hs.showError("")
            WatchForMeeting.logger.e("WatchForMeeting.sharing.key not valid. Make sure that key has been established on the server.")
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
         WatchForMeeting.logger.d("Connecting to server at "..WatchForMeeting.sharing.serverURL)
         _internal.connectionAttempts = _internal.connectionAttempts + 1
         _internal.websocketStatus = "connecting"
         _internal.server = hs.websocket.new(WatchForMeeting.sharing.serverURL, serverWebsocketCallback);
      else
         WatchForMeeting.logger.d("Starting Self Hosted Server on port "..WatchForMeeting.sharing.port)
         _internal.server = hs.httpserver.new()
         _internal.server:websocket("/ws", selfhostWebsocketCallback)
         _internal.websocketStatus = "open"
         _internal.server:setPort(WatchForMeeting.sharing.port)
         _internal.server:setCallback(selfhostHttpCallback)
         _internal.server:start()
      end
   end
end

--redefine retryConnection now that startConnection & stopConnection exist.
retryConnection = function()
   if(WatchForMeeting.sharing.maxConnectionAttempts > 0 and _internal.connectionAttempts >= WatchForMeeting.sharing.maxConnectionAttempts) then 
      WatchForMeeting.logger.e("Maximum Connection Attempts failed")
      stopConnection()
   elseif(_internal.connectionError) then
      stopConnection()
   else
      hs.timer.doAfter(WatchForMeeting.sharing.waitBeforeRetry, startConnection) 
   end
end


function validateShareSettings()
   WatchForMeeting.logger.d("validateShareSettings")
   if(WatchForMeeting.sharing.useServer and (WatchForMeeting.sharing.serverURL==nil or WatchForMeeting.sharing.key==nil)) then
      hs.showError("")
      if(WatchForMeeting.sharing.serverURL==nil) then WatchForMeeting.logger.e("WatchForMeeting.sharing.serverURL required when using a server") end
      if(WatchForMeeting.sharing.key==nil) then WatchForMeeting.logger.e("WatchForMeeting.sharing.key required when using a server") end
      return false
   elseif(not WatchForMeeting.sharing.useServer and WatchForMeeting.sharing.port==nil) then
      hs.showError("")
      WatchForMeeting.logger.e("WatchForMeeting.sharing.port required when self hosting")
      return false
   else
      return true
   end
end


-------------------------------------------
-- Methods
-------------------------------------------


--- WatchForMeeting:start()
--- Method
--- Starts a WatchForMeeting object
---
--- Parameters:
--- - None
---
--- Returns:
--- - The WatchForMeeting object
function WatchForMeeting:start()
   if(not _internal.running) then
      _internal.running = true
      if(self.sharing.enabled and validateShareSettings()) then
         startConnection()
      end
 
      if(self.menubar) then
         _internal.meetingMenuBar:returnToMenuBar()
      end
 
      if(_internal.mode == 1 ) then
         self:fake()
      else
         self:auto()
      end
   end
 
   return self
end
 
--- WatchForMeeting:stop()
--- Method
--- Stops a WatchForMeeting object
---
--- Parameters:
--- - None
---
--- Returns:
--- - The WatchForMeeting object
function WatchForMeeting:stop()
   _internal.running = false
   stopConnection()
 
   _internal.meetingMenuBar:removeFromMenuBar()
   _internal.zoomWindowFilter:pause()
   return self
end
 
--- WatchForMeeting:start()
--- Method
--- Restarts a WatchForMeeting object
---
--- Parameters:
--- - None
---
--- Returns:
--- - The WatchForMeeting object
function WatchForMeeting:restart()
   self:stop()
   return self:start()
end



--- WatchForMeeting:auto()
--- Method
--- Monitors Zoom and updates status accordingly
---
--- Parameters:
--- - None
---
--- Returns:
--- - The WatchForMeeting object
function WatchForMeeting:auto()
   _internal.mode = 0

   if(_internal.running) then
      _internal.faking = false
      _internal.meetingMenuBar:setMenu({
         { title = "Meeting Status:", disabled = true },
         { title = "Automatic", checked = true  },
         { title = "Busy", checked = false, fn=function() WatchForMeeting:fake() end }
      })
   
   
      --Check if a zoom meeting is already in progress
      _internal.zoom = hs.application.find("zoom.us")
      watchMeeting:fire()
      _internal.updateMenuIcon(currentlyInMeeting())
      if(_internal.server and _internal.websocketStatus == "open") then _internal.server:send(composeJsonUpdate(_internal.meetingState)) end
   
      --turn on the zoom window monitor
      _internal.zoomWindowFilter:resume()
   end
   
   return self
end
 

--- WatchForMeeting:fake()
--- Method
--- Disables monitoring and reports as being in a meeting. 
--- Useful when meeting type is not supported (currently any platform that isn't zoom.)
---
--- Parameters:
--- - None
---
--- Returns:
--- - The WatchForMeeting object
function WatchForMeeting:fake()
   _internal.mode = 1

   if(_internal.running) then
      _internal.faking = true

      _internal.meetingMenuBar:setMenu({
         { title = "Meeting Status:", disabled = true },
         { title = "Automatic", checked = false, fn=function() WatchForMeeting:auto() end  },
         { title = "Busy", checked = true }
      })
   
      _internal.zoomWindowFilter:pause()
   
      if(_internal.server and _internal.websocketStatus == "open") then _internal.server:send(composeJsonUpdate({mic_open = true, video_on = true, sharing = true})) end
      _internal.updateMenuIcon(true)
   end
 
   return self
end


-------------------------------------------
-- End of Methods
-------------------------------------------

return WatchForMeeting
