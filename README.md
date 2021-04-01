# WatchForMeeting
A Spoon for [Hammerspoon](http://hammerspoon.org) to answer the question
> Are you in a meeting?

Watches to see if:
1) Zoom is running
2) Are you on a call
3) Are you on mute, is your camera on, and/or are you screen sharing

And then lets you share that information.

# Installation & Basic Usage
Copy this directory as `WatchForMeeting.spoon` to `~/.hammerspoon/Spoons/`

To get going right out of the box, in your `~/.hammerspoon/init.lua` add these lines:
```
hs.loadSpoon("WatchForMeeting")
spoon.WatchForMeeting:start()
```

This will start the spoon monitoring for zoom calls, and come with the default status page, and menubar configurations.

# Sharing Status To A Webpage

## Default
In order to minimize dependencies, by default this spoon uses a [hs.httpserver](https://www.hammerspoon.org/docs/hs.httpserver.html) to host the status page. This comes with a significant downside of: only the last client to load the page will receive status updates. Any previously connected clients will remain stuck at the last update they received before that client connected.

Once you are running the spoon, assuming you haven't changed the port (and nothing else is running at that location) you can reach your status page at http://localhost:8080

## Better - MeetingStatusServer
For a better experience I recommend utilizing an external server to receive updates via websockets, and broadcast them to as many clients as you wish to connect.

For that purpose I've built [http://github.com/asp55/MeetingStatusServer](http://github.com/asp55/MeetingStatusServer) which runs on node.js and can either be run locally as its own thing, or hosted remotely.

If using the external server, you will to create a key to identify your "room" and then provide that information to the spoon. 
In that case, before `spoon.WatchForMeeting:start()` add the following to your `~/.hammerspoon/init.lua`

```
spoon.WatchForMeeting.sharing.useServer = true
spoon.WatchForMeeting.sharing.serverURL="[YOUR URL SERVER URL]"
spoon.WatchForMeeting.sharing.key="[YOUR KEY]"
```
