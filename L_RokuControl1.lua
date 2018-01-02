--[[

RokuControl plugin for MIOS Vera devices.

MIT License

Copyright (c) 2018 Brad D. Parker

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

--]]



local http = require("socket.http")
local ltn12 = require("ltn12")
local lom = require("lxp.lom")
local DEFAULT_POLL_DELAY = 60
local HADEVICE_SID = "urn:micasaverde-com:serviceId:HaDevice1"
local ROKU_DEVICE_SID = "urn:micasaverde-com:serviceId:RokuControl1"
local ROKU_CONTROL_SEND_KEYPRESS_CMD = "http://%s:%s/keypress/%s"
local ROKU_CONTROL_QUERY_CMD = "http://%s:%s/query/%s"
local ROKU_CONTROL_LAUNCH_CMD = "http://%s:%s/launch/%s"
local ROKU_CONTROL_INSTALL_CMD = "http://%s:%s/install/%s"
local ROKU_CONTROL_SEARCH_CMD = "http://%s:%s/search/browse?keyword=%s&title=%s&type=%s&tmsid=%s&provider-id=%s&launch=%s&season=%s&show-unavailable=%s&match-any=%s&provider=%s"

local THE_DEVICE
    
--  
-- Utility functions
--

--URL encode a string.
local function urlEncode(str)

  --Ensure all newlines are in CRLF form
  str = string.gsub (str, "\r?\n", "\r\n")

  --Percent-encode all non-unreserved characters
  --as per RFC 3986, Section 2.3
  --(except for space, which gets plus-encoded)
  str = string.gsub (str, "([^%w%-%.%_%~ ])",
    function (c) return string.format ("%%%02X", string.byte(c)) end)

  --Convert spaces to plus signs
  str = string.gsub (str, " ", "+")

  return str
end

-- extract element from xml
local function extractXmlElement(tag, xml, default)
   local tab = lom.parse (xml)
   for index, value in ipairs(tab) do
     if (value["tag"] == tag) then
        return value[1]
      end
   end
   -- not found return default
   return default
end

-- String or number to boolean
local function toboolean(v)
   return (type(v) == "string" and string.upper(v) == "TRUE") or 
          (type(v) == "number" and v ~= 0) or 
          (type(v) == "boolean" and v)
end

-- Wake on lan
local function wakeOnLan()
   local mac  = luup.devices[THE_DEVICE].mac
   local command = "wol " .. mac
   
   local retCode = os.execute (command)

   if (wolRetCode == 0) then
      luup.log("(RokuControl:wakeOnLan) Wake-on-lan succeeded.")
   else
      luup.log("(RokuControl:wakeOnLan) Wake-on-lan failed with return code " .. retCode)
   end
end

local function http_request(method, headers, url, request_body)
   luup.log("(RokuControl:http_request) Calling url: " .. url)
   local response = nil
   if (method == "GET") then
     local success
     success, response, status = luup.inet.wget(url, 5)
   else
       local response_body = {}
      local dummy, status, header = socket.http.request{
         method = method,
         url = url,
         headers = headers,
         source = ltn12.source.string(request_body),
         sink = ltn12.sink.table(response_body)
      }
         
      if response_body ~= nil then
         response = table.concat(response_body)
      end
   end

   return response, status, header
end

local function cmdSendKeyPress(key)
   local ipAddress = luup.devices[THE_DEVICE].ip
   local port = luup.variable_get(ROKU_DEVICE_SID, "Port", THE_DEVICE)
   if (ipAddress == nil) then
      luup.log("(RokuControl:cmdSendKeyPress) Error: no ip specified!")
   else
      local content, status, header = 
         http_request("POST", 
                      {["Accept"] = "application/json"}, 
                      ROKU_CONTROL_SEND_KEYPRESS_CMD:format(ipAddress, port, key), 
                      "")
      if (status ~= 200 or content:find('{"bool"') == nil or content:find('"true"') == nil) then
         luup.log("(RokuControl:cmdSendKeyPress) Error sending key press action=" .. key .. 
                  ", status=" .. (status or "No status") .. 
                  ", content=" .. (content or "No content"))
      end
   end
end

local function cmdLaunch(appId)
   local ipAddress = luup.devices[THE_DEVICE].ip
   local port = luup.variable_get(ROKU_DEVICE_SID, "Port", THE_DEVICE)
   if (ipAddress == nil) then
      luup.log("(RokuControl:cmdLaunch) Error: no ip specified!")
   else
       local url = ROKU_CONTROL_LAUNCH_CMD:format(ipAddress, port, appId)
      local content, status, header = http_request("POST", {["Accept"] = "application/json"}, url, "")
      if (status ~= 200 or content:find('{"bool"') == nil or content:find('"true"') == nil) then
         luup.log("(RokuControl:cmdLaunch) Error sending launch action=" .. url .. 
         ", status=" .. (status or "No status") .. 
         ", content=" .. (content or "No content"))
      end
   end
end

local function cmdInstall(appId)
   local ipAddress = luup.devices[THE_DEVICE].ip
   local port = luup.variable_get(ROKU_DEVICE_SID, "Port", THE_DEVICE)
   if (ipAddress == nil) then
      luup.log("(RokuControl:cmdInstall) Error: no ip specified!")
   else
      local url = ROKU_CONTROL_INSTALL_CMD:format(ipAddress, port, appId)
      local content, status, header = http_request("POST", {["Accept"] = "application/json"}, url, "")
      if (status ~= 200 or content:find('{"bool"') == nil or content:find('"true"') == nil) then
         luup.log("Error sending install action=" .. url .. ", status=" .. (status or "No status") .. ", content=" .. (content or "No content"))
      end
   end
end

-- Search for content
local function cmdSearch(keyword, title, type, tmsid, season, 
                         showUnavailable, matchAny, providerId, provider, launch)
   local ipAddress = luup.devices[THE_DEVICE].ip
   local port = luup.variable_get(ROKU_DEVICE_SID, "Port", THE_DEVICE)
   if (ipAddress == nil) then
      luup.log("(RokuControl:cmdSearch) Error: no ip specified!")
   else
   --"http://%s:%s/search/browse?keyword=%s&title=%s&type=%s&tmsid=%s&provider-id=%s&launch=%s&season=%s&show-unavailable=%s&match-any=%s&provider=%s"
       local url = ROKU_CONTROL_SEARCH_CMD:format(urlEncode(ipAddress), 
                                                  urlEncode(port),
                                                  urlEncode(keyword),
                                                  urlEncode(title), 
                                                  urlEncode(type), 
                                                  urlEncode(tmsid), 
                                                  urlEncode(providerId), 
                                                  tostring(toboolean(launch)),
                                                  urlEncode(season), 
                                                  tostring(toboolean(showUnavailable)), 
                                                  tostring(toboolean(matchAny)), 
                                                  urlEncode(provider))
      local content, status, header = http_request("POST", {["Accept"] = "application/json"}, url, "")
      if (status ~= 200) then
         luup.log("(RokuControl:cmdSearch) Error sending search action=" .. url .. 
                  ", status=" .. (status or "No status") .. 
                  ", content=" .. (content or "No content"))
      end
   end
end

-- Execute a query to the Roku
local function cmdGetQueryResult(type)
   luup.log("(RokuControl:cmdGetQueryResult) Querying Roku status")
   local ipAddress = luup.devices[THE_DEVICE].ip
   local port = luup.variable_get(ROKU_DEVICE_SID, "Port", THE_DEVICE)
   if (ipAddress ~= nil) then
      local state, title, subtitle, description
      local url = ROKU_CONTROL_QUERY_CMD:format(ipAddress, port, type)
      local content, status, header = http_request("GET", {["Accept"] = "application/xml"}, url, "")

      if (status ~= 200) then
         luup.log("(RokuControl:cmdGetQueryResult) Error querying Roku, status=" .. tostring(status) .. ", response=" .. content)
         state = "error"
         title = "error"
         subtitle = "error"
         description = "error"
      else
      
         luup.log("(RokuControl:cmdGetQueryResult) Roku returned " .. tostring(content))
         return tostring(content)
      end
   end
   return nil

end

-- Poll the device for status
function rokuControlPoll(source)
   luup.log("(RokuControl:rokuControlPoll) Polling Roku device info")
   local lastUpdate = tonumber(luup.variable_get(ROKU_DEVICE_SID, "LastUpdate", THE_DEVICE), 10)
   luup.variable_set(ROKU_DEVICE_SID, "LastUpdate", os.time(), THE_DEVICE)
   local updateInterval = tonumber(luup.variable_get(HADEVICE_SID, "PollMinDelay", THE_DEVICE), 10)
   local devicexml = cmdGetQueryResult("device-info")
   if (devicexml == nil) then
      luup.log("(RokuControl:rokuControlPoll) Unable to get Roku device info")
      luup.variable_set(ROKU_DEVICE_SID, "power_mode", "", THE_DEVICE)
   else
      luup.log("(RokuControl:rokuControlPoll) Got Roku device info")
      luup.variable_set(ROKU_DEVICE_SID, 
                        "power_mode", 
                        extractXmlElement("power-mode", devicexml, nil), 
                        THE_DEVICE)
   end
   queryActiveApp()
   if (source ~= "command" or ((os.time() - lastUpdate) >= updateInterval)) then
      rokuControlRefreshPoll()
   end
end

-- Query for the active app. If homescreen, app will be "Roku" with no ID.
function queryActiveApp()
   luup.log("(RokuControl:queryActiveApp) Querying active apps")
   local appsxml = cmdGetQueryResult("active-app")
   local apps = {}
   if (appsxml == nil) then
           luup.variable_set(ROKU_DEVICE_SID, "active_app", "", THE_DEVICE)
           luup.variable_set(ROKU_DEVICE_SID, "active_app_id", "", THE_DEVICE)   
   else
      local tab = lom.parse (appsxml)
      
      -- There should only be one app, although there could also be a "screensaver" tag
      for index, value in ipairs(tab) do
         if (value["tag"] == "app") then
           luup.variable_set(ROKU_DEVICE_SID, "active_app", value[1], THE_DEVICE)
           luup.variable_set(ROKU_DEVICE_SID, "active_app_id", value["attr"]["id"], THE_DEVICE)
         end
      end
   end
   
end

-- This is cool, but of limited usefulness without some major javascripty front end stuff
local function queryRokuApps()
   luup.log("(RokuControl:queryRokuApps) Querying Roku apps")
   local appsxml = cmdGetQueryResult("apps")
   local apps = {}
   local appCount = 0
   if (appsxml ~= nil) then
      local tab = lom.parse (appsxml)
      for index, value in ipairs(tab) do
         if (value["tag"] == "app") then
            appCount = appCount + 1
            apps[appCount] = {}
            apps[appCount]["id"] = value["attr"]["id"]
            apps[appCount]["name"] = value[1]
         end
      end
   end
end

-- Sets the device variable if it is currently nil. If forceUpdate is true, sets regardless of existing value
local function setIfNil(key, value, forceUpdate)
   if (forceUpdate or luup.variable_get(ROKU_DEVICE_SID, key, THE_DEVICE) == nil) then
      luup.variable_set(ROKU_DEVICE_SID, key, value, THE_DEVICE)
   end
end

-- Updates device info. If forceUpdate is true, will override existing values
local function queryDeviceInfo(forceUpdate)
   luup.log("(RokuControl:queryDeviceInfo) Querying Roku device info")
   local devicexml = cmdGetQueryResult("device-info")
   if (devicexml == nil) then
      return false
   else
      luup.log("(RokuControl:queryDeviceInfo) Got Roku device info")
      
      if (forceUpdate or luup.attr_get('mac', THE_DEVICE) == nil) then
         if (extractXmlElement("network-type", devicexml, nil) == "wifi") then
            luup.log("(RokuControl:queryDeviceInfo) using wifi")
            luup.attr_set('mac', extractXmlElement("wifi-mac", devicexml, nil), THE_DEVICE)
         elseif (extractXmlElement("network-type", devicexml, nil) == "ethernet") then
            luup.log("(RokuControl:queryDeviceInfo) using ethernet")
            luup.attr_set('mac', extractXmlElement("ethernet-mac", devicexml, nil), THE_DEVICE)   
         end
      end
      
      if (forceUpdate or luup.attr_get('name', THE_DEVICE) == nil) then
         luup.attr_set('name', extractXmlElement("user-device-name", devicexml, nil), THE_DEVICE)
      end
      
      if (forceUpdate or luup.attr_get('manufacturer', THE_DEVICE) == nil) then
         luup.attr_set('manufacturer', extractXmlElement("vendor-name", devicexml, nil), THE_DEVICE)
      end
      
      if (forceUpdate or 
         luup.attr_get('model', THE_DEVICE) == nil or 
         luup.attr_get('model', THE_DEVICE) == ": ") then
         luup.attr_set('model', extractXmlElement("model-name", devicexml, "") .. ": " .. 
                                extractXmlElement("model-number", devicexml, "") , 
                       THE_DEVICE)
      end
      
      setIfNil("user_device_name", extractXmlElement("user-device-name", devicexml, nil), forceUpdate)
      setIfNil("serial_number", extractXmlElement("serial-number", devicexml, nil), forceUpdate)
      setIfNil("is_tv", extractXmlElement("is-tv", devicexml, nil), forceUpdate)
      setIfNil("screen_size", extractXmlElement("screen-size", devicexml, nil), forceUpdate)
      setIfNil("software_version", extractXmlElement("software-version", devicexml, nil), forceUpdate)
      setIfNil("software_build", extractXmlElement("software-build", devicexml, nil), forceUpdate)
      setIfNil("supports_suspend", extractXmlElement("supports-suspend", devicexml, nil), forceUpdate)
      setIfNil("supports_find_remote", extractXmlElement("supports-find-remote", devicexml, nil), forceUpdate)
      setIfNil("supports_search", extractXmlElement("search-enabled", devicexml, nil), forceUpdate)
      setIfNil("supports_channel_search", extractXmlElement("search-channels-enableld", devicexml, nil), forceUpdate)
      setIfNil("supports_warm_standby", extractXmlElement("supports-warm-standby", devicexml, nil), forceUpdate)
      setIfNil("supports_wake_on_wlan", extractXmlElement("supports-wake-on-wlan", devicexml, nil), forceUpdate)
   end
   
   rokuControlPoll("queryDeviceInfo")
   return true
end

-- Sets up the next poll
function rokuControlRefreshPoll()
   local pollingEnabled = toboolean(luup.variable_get(HADEVICE_SID, "PollingEnabled", THE_DEVICE))
   local pollMinDelay = tonumber(luup.variable_get(HADEVICE_SID, "PollMinDelay", THE_DEVICE), 10)
   if (pollingEnabled) then 
      luup.log("(RokuControl:rokuControlRefreshPoll) Setting up next poll")
      luup.call_timer("rokuControlPoll",1, pollMinDelay, "refresh")
   end                 
end

-- Plugin device startup
function rokuControlStartup(device)
   luup.log("(RokuControl:rokuControlStartup) Starting roku setup")
   THE_DEVICE = device

   -- A/V device
   luup.attr_set('category_num', 15, THE_DEVICE)
   
   local ipAddress = luup.devices[device].ip
   local port = luup.variable_get(ROKU_DEVICE_SID, "Port", device)

   if (ipAddress == nil) then
      luup.log("(RokuControl:rokuControlStartup) No IP Address specified")
      luup.task('Set IP Address for Roku Control device',2,'RokuControl Plugin',-1)
      return false
   end
   if (port == nil) then
      luup.log("(RokuControl:rokuControlStartup) No Port specified. Falling back to default 8060.")
      luup.variable_set(ROKU_DEVICE_SID, "Port", "8060", device)
   end
   
   -- reload port
   ipAddress = luup.devices[device].ip
   port = luup.variable_get(ROKU_DEVICE_SID, "Port", device)

   luup.log("(RokuControl:rokuControlStartup) Querying Roku for device information")
   local querySuccess = queryDeviceInfo(false)
   if (querySuccess ~= true) then
      if(luup.devices[THE_DEVICE].mac == nil) then
         luup.task('Could not communicate with Roku device. Make sure the device is powered on, then click "Force Update of Device Info" under "Apps and Update"',
                   2, 'RokuControl Plugin', -1)
      end
   end
   
   luup.log("(RokuControl:rokuControlStartup) Starting roku polling setup")
   
   -- make sure we have the polling defined
   local pollingEnabled = luup.variable_get(HADEVICE_SID, "PollingEnabled", THE_DEVICE)
   if (pollingEnabled == nil) then
      pollingEnabled = "true"
      luup.variable_set(HADEVICE_SID, "PollingEnabled", pollingEnabled, THE_DEVICE)
   end
   pollingEnabled = toboolean(pollingEnabled)
   
   local pollMinDelay = luup.variable_get(HADEVICE_SID, "PollMinDelay", THE_DEVICE)
   if (pollMinDelay == nil) then
      pollMinDelay = DEFAULT_POLL_DELAY
      luup.variable_set(HADEVICE_SID, "PollMinDelay", pollMinDelay, THE_DEVICE)
   end
   pollMinDelay = tonumber(pollMinDelay, 10)
   
   
   if (pollingEnabled) then
      luup.log("(RokuControl:rokuControlStartup) Setting up startup polling")
      luup.call_delay("rokuControlPoll", 5, "startup")
   end
   
   luup.log("(RokuControl:rokuControlStartup) Roku setup done")
   luup.set_failure(false)
   return true, "Good to go", "RokuControl"
end
