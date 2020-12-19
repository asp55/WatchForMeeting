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

local function httpCallback()
   return [[<!DOCTYPE html>
      <html>
      <head>
         <title>Zoom Panel</title>
         <meta name="viewport" content="width=device-width; initial-scale=1.0; maximum-scale=1.0; user-scalable=0;" /> 
         <link href="https://fonts.googleapis.com/css2?family=Barlow:wght@600&display=swap" rel="stylesheet">
         <style type="text/css">
            :root {
                  --window-height: 100vh;
            }
            body {
                  margin: 0;
                  padding: 16px;
                  column-gap: 16px;
                  row-gap: 0;
                  display: grid;
                  grid-template-columns: 1fr 1fr 1fr;
                  grid-template-rows: calc(100vh - 32px) 0;
                  justify-items: center;
                  align-items: center;
                  text-align: center;
                  width: calc(100vw - 32px);
                  height: calc(var(--window-height) - 32px);
                  transition: grid-template-rows .25s ease-in-out, row-gap .25s ease-in-out;
            }
            body.busy {
                  grid-template-rows: calc((var(--window-height) - 48px) * 0.625) calc((var(--window-height) - 48px) * 0.375);
                  row-gap: 16px;
                  transition: grid-template-rows .25s ease-in-out, row-gap .25s ease-in-out;
            }

            svg {
                  width: 100%;
                  height: 100%;
            }

            body #status{
                  background: #fff;
                  width: 100%;
                  height: 100%;
                  grid-area: 1 / 1 / span 1 / span 3;
                  transition: background .25s ease-in-out;
            }
            body.free #status{
                  background: #93E0FF;
            }
            body.busy #status{
                  background: #C80037;
            }
            body.offline #status{
                  background: #ccc;
            }

            body #mic,
            body #vid,
            body #screenshare {
                  grid-row-start: 2;
                  grid-row-end: span 1;
                  grid-column-end: span 1;

                  width: 100%;
                  height: 100%;
                  display: grid;
                  grid-template-rows: 1fr;
                  grid-template-columns: 1fr;
                  justify-items: center;
                  align-items: center;
                  transition: background .25s ease-in-out;

            }
            body #mic svg,
            body #vid svg,
            body #screenshare svg {
                  width: 75%;
                  height: 75%;
                  max-width: 140px;
                  max-height: 140px;
                  transition: fill .25s ease-in-out;
            }
            body #mic {
                  grid-column-start: 1;
            }
            body #vid {
                  grid-column-start: 2;
            }
            body #screenshare {
                  grid-column-start: 3;
            }
            body .off {
                  background: #fff;
            }
            body .off svg {
                  fill: #C80037;
            }
            body .on {
                  background: #C80037;
            }
            body .on svg {
                  fill: #fff;
            }
         </style>
         <script type="text/javascript">

         function startWebsocket() {
            var ws = new WebSocket('ws://]]..hs.network.interfaceDetails(hs.network.primaryInterfaces())["IPv4"]["Addresses"][1]..[[:12345/ws')

            ws.onopen = () => {
                  console.log("WebSocket is open now.");
                  ws.send('Connected')
            }

            ws.onerror = (error) => {
               console.log(`WebSocket error: ${error}`)
            }

            ws.onclose = (event) => {
                  console.log("WebSocket is closed now. Reconnecting in 0.5s");
                  offlinePanel();
                  // connection closed, discard old websocket and create a new one in 0.5s
                  ws = null
                  setTimeout(startWebsocket, 500)
            };

            ws.onmessage = (e) => {
               var json = JSON.parse(e.data);
               if(json.type === "update") {
                  updatePanel(json.inZoom);
               }
            }

            return ws;
         }


         function htmlToElement(html) {
            var template = document.createElement('template');
            html = html.trim(); // Never return a text node of whitespace as the result
            template.innerHTML = html;
            return template.content.firstChild;
         }

         var statusSVG = htmlToElement(`<svg viewBox="0 0 1168 476" preserveAspectRatio="xMidYMid meet">
         <text x="584" y="238" fill="white" font-family="Barlow-SemiBold, Barlow" font-size="180" font-weight="600" text-anchor="middle">
            <tspan dy=".35em" id="statusLabel"></tspan>
         </text>
      </svg>`);

         var micStatus = htmlToElement(`<div id="mic"></div>`);
         var micMutedSVG = htmlToElement(`<svg viewBox="0 0 140 140" preserveAspectRatio="xMidYMid meet" id="muted">
         <path d="M70,116.666667 C45.8482041,116.640946 26.2757208,97.0684626 26.25,72.9166667 L26.25,58.3333333 C26.25,55.1116723 23.6383277,52.5 20.4166667,52.5 C17.1950056,52.5 14.5833333,55.1116723 14.5833333,58.3333333 L14.5833333,72.9166667 C14.618151,100.763045 35.2830553,124.272431 62.895,127.878333 C63.6236456,127.969754 64.1694302,128.590647 64.1666667,129.325 L64.1666667,134.166667 C64.1666667,137.388328 66.778339,140 70,140 C73.221661,140 75.8333333,137.388328 75.8333333,134.166667 L75.8333333,129.325 C75.8305698,128.590647 76.3763544,127.969754 77.105,127.878333 C85.1171446,126.841648 92.8027249,124.053409 99.6158333,119.711667 C99.9900252,119.474686 100.236238,119.08049 100.285026,118.640264 C100.333814,118.200038 100.179889,117.761497 99.8666667,117.448333 L93.5025,111.084167 C93.0378562,110.622017 92.3219989,110.52657 91.7525,110.850833 C85.1387306,114.667306 77.6359258,116.673285 70,116.666667 L70,116.666667 Z M37.4908333,55.1075 C37.0744586,54.6900684 36.4476954,54.5644178 35.9025932,54.7890969 C35.3574911,55.0137761 35.001303,55.5445775 35,56.1341667 L35,72.9166667 C35.0010997,84.8026083 41.0343231,95.8756841 51.0210525,102.320903 C61.0077818,108.766122 73.5829931,109.702527 84.4141667,104.8075 C84.8406328,104.607982 85.144536,104.214842 85.2301862,103.751868 C85.3158364,103.288894 85.1726951,102.81305 84.8458333,102.474167 L37.4908333,55.1075 Z M138.290833,130.083333 L115.2375,107.03 C114.730167,106.52719 114.665746,105.729362 115.085833,105.151667 C121.823826,95.7554963 125.437766,84.4790244 125.416667,72.9166667 L125.416667,58.3333333 C125.416667,55.1116723 122.804994,52.5 119.583333,52.5 C116.361672,52.5 113.75,55.1116723 113.75,58.3333333 L113.75,72.9166667 C113.760873,81.1774303 111.419922,89.2706028 107.000833,96.25 C106.763152,96.6237129 106.367952,96.8685652 105.9275,96.915 C105.495996,96.9604213 105.06711,96.8081667 104.760833,96.5008333 L100.514167,92.26 C100.055822,91.7930311 99.9629509,91.0786367 100.286667,90.51 C103.39252,85.1682847 105.019405,79.0956527 105,72.9166667 L105,35 C104.992309,17.600931 92.2049862,2.84923948 74.9831661,0.37202804 C57.7613461,-2.1051834 41.334662,8.44432312 36.4233333,25.1358333 C36.2752647,25.6279438 35.8800368,26.0064018 35.3819727,26.133008 C34.8839086,26.2596142 34.355929,26.1158325 33.9908333,25.7541667 L9.9575,1.75 C7.66277634,-0.486273262 4.00389033,-0.486273262 1.70916667,1.75 C-0.568061307,4.0279158 -0.568061307,7.72041753 1.70916667,9.99833333 L130.0425,138.331667 L130.0425,138.331667 L130.0425,138.331667 L130.083333,138.3725 C132.406127,140.443348 135.945475,140.326277 138.126346,138.106461 C140.307217,135.886646 140.361631,132.34578 138.25,130.06 L138.290833,130.083333 Z"/>
      </svg>`);
         var micUnmutedSVG = htmlToElement(`<svg viewBox="0 0 140 140" preserveAspectRatio="xMidYMid meet" id="unmuted">
         <path d="M70,140 C73.5,140 75.8333333,137.666667 75.8333333,134.166667 L75.8333333,129.5 C75.8333333,128.916667 76.4166667,128.333333 77,128.333333 C104.416667,124.833333 125.416667,101.5 125.416667,73.5 L125.416667,58.3333333 C125.416667,54.8333333 123.083333,52.5 119.583333,52.5 C116.083333,52.5 113.75,54.8333333 113.75,58.3333333 L113.75,72.9166667 C113.75,96.8333333 93.9166667,116.666667 70,116.666667 C46.0833333,116.666667 26.25,96.8333333 26.25,72.9166667 L26.25,58.3333333 C26.25,54.8333333 23.9166667,52.5 20.4166667,52.5 C16.9166667,52.5 14.5833333,54.8333333 14.5833333,58.3333333 L14.5833333,72.9166667 C14.5833333,100.916667 35,124.25 63,127.75 C63.5833333,127.75 64.1666667,128.333333 64.1666667,128.916667 L64.1666667,134.166667 C64.1666667,137.666667 66.5,140 70,140 Z M70,107.916667 L70,107.916667 C89.25,107.916667 105,92.1666667 105,72.9166667 L105,35 C105,15.75 89.25,0 70,0 L70,0 C50.75,0 35,15.75 35,35 L35,72.9166667 C35,92.1666667 50.75,107.916667 70,107.916667 Z" />
      </svg>`);


         var vidStatus = htmlToElement(`<div id="vid"></div>`);
         var vidOffSVG = htmlToElement(`<svg viewBox="0 0 140 140" preserveAspectRatio="xMidYMid meet" id="vidoff">
         <path d="M18.4625,37.52 C18.0333847,37.0944592 17.3869091,36.9762862 16.835,37.2225 C13.6893741,38.6337568 11.6656953,41.7606374 11.6666663,45.2083333 L11.6666663,97.7083333 C11.6666663,102.540825 15.5841751,106.458336 20.4166667,106.458336 L83.8775,106.458336 C84.4681509,106.45939 85.0011122,106.104067 85.2272876,105.558435 C85.4534629,105.012803 85.3281825,104.384625 84.91,103.9675 L18.4625,37.52 Z M126.799167,43.4641667 L109.299167,53.445 C106.662886,54.9294253 105.022706,57.7112777 105,60.7366667 L105,82.18 C105.02512,85.20472 106.66464,87.9854529 109.299167,89.4716667 L126.799167,99.4525 C129.466246,101.029886 132.76868,101.079055 135.481536,99.581769 C138.194393,98.084483 139.91304,95.2640681 140,92.1666667 L140,50.75 C139.91304,47.6525985 138.194393,44.8321837 135.481536,43.3348976 C132.76868,41.8376116 129.466246,41.8867805 126.799167,43.4641667 L126.799167,43.4641667 Z M99.5925,91.3441667 C99.3186207,91.0705084 99.1653304,90.6988319 99.1666667,90.3116667 L99.1666667,45.2083333 C99.1666667,40.3758418 95.2491582,36.4583333 90.4166667,36.4583333 L45.3133333,36.4583333 C44.9261681,36.4596696 44.5544916,36.3063793 44.2808333,36.0325 L9.9575,1.70916667 C7.98091166,-0.265894464 4.88135785,-0.561905522 2.56666667,1.00333333 C2.25868982,1.21034001 1.97151255,1.44672403 1.70916667,1.70916667 C-0.568061307,3.98708247 -0.568061307,7.6795842 1.70916667,9.9575 L130.0425,138.290833 C132.331377,140.501505 135.969661,140.469889 138.219775,138.219775 C140.469889,135.969661 140.501505,132.331377 138.290833,130.0425 L99.5925,91.3441667 Z"/>
      </svg>`);
         var vidOnSVG = htmlToElement(`<svg viewBox="0 0 140 140" preserveAspectRatio="xMidYMid meet" id="vidon">
         <path d="M126.583333,43.75 L109.083333,53.6666667 C106.75,54.8333333 105,57.75 105,60.6666667 L105,82.25 C105,85.1666667 106.75,88.0833333 109.083333,89.25 L126.583333,99.1666667 C130.666667,101.5 135.916667,100.333333 138.833333,96.25 C139.416667,95.0833333 140,93.3333333 140,92.1666667 L140,50.75 C140,46.0833333 135.916667,42 131.25,42 C129.5,42 128.333333,42.5833333 126.583333,43.75 Z M90.4166667,36.1666667 L20.4166667,36.1666667 C15.75,36.1666667 11.6666667,40.25 11.6666667,45.5 L11.6666667,97.4166667 C11.6666667,102.666667 15.75,106.166667 20.4166667,106.166667 L89.8333333,106.166667 C95.0833333,106.166667 98.5833333,102.083333 98.5833333,97.4166667 L98.5833333,45.5 C99.1666667,40.25 95.0833333,36.1666667 90.4166667,36.1666667 Z" />
      </svg>`);


         var screenshareStatus = htmlToElement(`<div id="screenshare"></div>`);
         var screenshareOffSVG = htmlToElement(`<svg viewBox="0 0 140 140" preserveAspectRatio="xMidYMid meet" id="screenshareon">
         <path d="M99.39,120.37 C93.5077687,118.089653 87.3519962,116.590213 81.08,115.91 C80.4525944,115.834164 79.9804891,115.301972 79.98,114.67 L79.98,100.84 C80.0021104,99.8843643 79.6421907,98.9593706 78.98,98.27 L61.98,81.27 C61.1816244,80.4787648 60.1040309,80.0333595 58.98,80.03 L22.5,80.03 C21.8317281,80.0300481 21.1912543,79.7625419 20.7215413,79.2871924 C20.2518284,78.8118429 19.9919807,78.1682238 20,77.5 L20,40 C19.9968077,39.5548714 19.8211671,39.1283155 19.51,38.81 L12.87,32.18 C12.3843669,31.6921881 11.6502965,31.5499668 11.0176202,31.8211138 C10.3849439,32.0922608 9.98167624,32.7219127 9.9994007,33.41 L9.9994007,92.5 C9.9994007,96.6421356 13.3578644,100 17.5,100 L58.75,100 C59.4403559,100 60,100.559644 60,101.25 L60,114.67 C60.0040504,115.303688 59.5296506,115.838466 58.9,115.91 C52.6316729,116.586834 46.4791982,118.082928 40.6,120.36 C38.370177,121.255051 37.0922941,123.609615 37.5569273,125.967016 C38.0215604,128.324418 40.0973135,130.017996 42.5,130.000142 L97.5,130.000142 C99.8910652,130.00114 101.948293,128.309243 102.408783,125.962939 C102.869272,123.616634 101.604127,121.272683 99.39,120.37 Z M138.24,129.76 L108.49,100 L122.49,100 C126.632136,100 129.99,96.6421356 129.99,92.5 L129.99,17.5 C129.99,13.3578644 126.632136,10 122.49,10 L18.49,10 L10.24,1.76 C7.89745963,-0.579627024 4.10254037,-0.579627024 1.76,1.76 L1.76,1.76 C-0.579627024,4.10254037 -0.579627024,7.89745963 1.76,10.24 L129.76,138.24 C132.10254,140.579627 135.89746,140.579627 138.24,138.24 L138.24,138.24 C140.579627,135.89746 140.579627,132.10254 138.24,129.76 L138.24,129.76 Z M117.5,20 C118.880712,20 120,21.1192881 120,22.5 L120,77.5 C120,78.8807119 118.880712,80 117.5,80 L88.5,80 L28.5,20 L117.5,20 Z" />
      </svg>`);
         var screenshareOnSVG = htmlToElement(`<svg viewBox="0 0 140 140" preserveAspectRatio="xMidYMid meet" id="screenshareon">
         <path d="M122.5,10 L17.5,10 C13.3578644,10 10,13.3578644 10,17.5 L10,92.5 C10,96.6421356 13.3578644,100 17.5,100 L58.75,100 C59.4403559,100 60,100.559644 60,101.25 L60,114.67 C60.0040504,115.303688 59.5296506,115.838466 58.9,115.91 C52.6316729,116.586834 46.4791982,118.082928 40.6,120.36 C38.370177,121.255051 37.0922941,123.609615 37.5569273,125.967016 C38.0215604,128.324418 40.0973135,130.017996 42.5,130.000142 L97.5,130.000142 C99.8910652,130.000142 101.948293,128.309243 102.408783,125.962939 C102.869272,123.616634 101.604127,121.272683 99.39,120.37 C93.5077687,118.089653 87.3519962,116.590213 81.08,115.91 C80.4525944,115.834164 79.9804891,115.301972 79.98,114.67 L79.98,101.25 C79.98,100.559644 80.5396441,100 81.23,100 L122.5,100 C126.642136,100 130,96.6421356 130,92.5 L130,17.5 C130,13.3578644 126.642136,10 122.5,10 Z M120,77.5 C120,78.8807119 118.880712,80 117.5,80 L22.5,80 C21.1192881,80 20,78.8807119 20,77.5 L20,22.5 C20,21.1192881 21.1192881,20 22.5,20 L117.5,20 C118.880712,20 120,21.1192881 120,22.5 L120,77.5 Z" />
      </svg>`);

         function updatePanel(inZoom) {
            console.log(inZoom);
            var panel = document.getElementsByTagName("BODY")[0];
            var status = document.getElementById("status");
            
            if(status.classList.contains("init")) {
                  status.classList.remove("init");
                  status.innerHTML = "";
                  status.appendChild(statusSVG);
            }

            panel.classList.remove("offline");

            if(!inZoom) {
                  panel.classList.remove("busy");
                  panel.classList.add("free");
                  statusSVG.getElementById("statusLabel").innerHTML = "FREE";

                  if(micStatus.parentNode === panel) panel.removeChild(micStatus);
                  if(vidStatus.parentNode === panel) panel.removeChild(vidStatus);
                  if(screenshareStatus.parentNode === panel) panel.removeChild(screenshareStatus);
            }
            else {
                  panel.classList.remove("free");
                  panel.classList.add("busy");
                  statusSVG.getElementById("statusLabel").innerHTML = "MEETING";

                  if(micStatus.parentNode !== panel) panel.appendChild(micStatus);
                  if(vidStatus.parentNode !== panel) panel.appendChild(vidStatus);
                  if(screenshareStatus.parentNode !== panel) panel.appendChild(screenshareStatus);

                  micStatus.innerHTML = "";
                  if(inZoom.mic_open) {
                     micStatus.classList.remove("off");
                     micStatus.classList.add("on");
                     micStatus.appendChild(micUnmutedSVG);
                  }
                  else {
                     micStatus.classList.remove("on");
                     micStatus.classList.add("off");
                     micStatus.appendChild(micMutedSVG);
                  }

                  vidStatus.innerHTML = "";
                  if(inZoom.video_on) {
                     vidStatus.classList.remove("off");
                     vidStatus.classList.add("on");
                     vidStatus.appendChild(vidOnSVG);
                  }
                  else {
                     vidStatus.classList.remove("on");
                     vidStatus.classList.add("off");
                     vidStatus.appendChild(vidOffSVG);
                  }

                  screenshareStatus.innerHTML = "";
                  if(inZoom.sharing) {
                     screenshareStatus.classList.remove("off");
                     screenshareStatus.classList.add("on");
                     screenshareStatus.appendChild(screenshareOnSVG);
                  }
                  else {
                     screenshareStatus.classList.remove("on");
                     screenshareStatus.classList.add("off");
                     screenshareStatus.appendChild(screenshareOffSVG);

                  }
            }
         }

         function offlinePanel() {
            var panel = document.getElementsByTagName("BODY")[0];
            var status = document.getElementById("status");

            panel.classList.remove("busy");
            panel.classList.remove("free");
            panel.classList.add("offline");

            if(status.classList.contains("init")) {
                  status.classList.remove("init");
                  status.innerHTML = "";
                  status.appendChild(statusSVG);
            }
            
            statusSVG.getElementById("statusLabel").innerHTML = "OFFLINE";



         }

      var socket = startWebsocket();
         </script>
      </head>
      <body>
         <div id="status" class="init">Initializing...</div>
      </body>
      </html>]], 200, {}
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

local function inMeeting()
   return (obj.zoom ~= nil and obj.zoom:getMenuItems()[2].AXTitle == "Meeting")
end

--declare startStopWatchMeeting before watchMeeting, define it after.
local startStopWatchMeeting = function() end

local watchMeeting = hs.timer.new(0.5, function()
   -- If the second menu isn't called "Meeting" then zoom is no longer in a meeting
    if(inMeeting() == false) then
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
   if(obj.meetingState == false and inMeeting() == true) then
      obj.logger.d("Start Meeting")
         obj.meetingState = {}
         watchMeeting:start()
         watchMeeting:fire()
   elseif(obj.meetingState and inMeeting() == false) then
      obj.logger.d("End Meeting")
      watchMeeting:stop()
      obj.meetingState = false
      server:send(panelJSON())
   end
end

local function checkMeetingStatus(window, name, event)
	obj.logger.d("Check Meeting Status",window,name,event)
   obj.zoom = hs.application.find("zoom.us")
   
   startStopWatchMeeting()

end

-- Monitor zoom for running meeting
hs.application.enableSpotlightForNameSearches(true)
local windowFilter = hs.window.filter.new('zoom.us',"WindowFilterLog",0)
windowFilter:subscribe(hs.window.filter.hasWindow,checkMeetingStatus,true)
windowFilter:subscribe(hs.window.filter.hasNoWindows,checkMeetingStatus)
windowFilter:subscribe(hs.window.filter.windowDestroyed,checkMeetingStatus)
windowFilter:subscribe(hs.window.filter.windowTitleChanged,checkMeetingStatus)
windowFilter:pause() 

-------------------------------------------
-- End of Zoom Monitor
-------------------------------------------

function obj:start()
   server:websocket("/ws", websocketCallback)
   server:setPort(self.port)
   server:setCallback(httpCallback)
   server:start()
   windowFilter:resume()
   return self
end

function obj:stop()
   server:stop()
   windowFilter:pause()
end

return obj
