#!/usr/bin/lua
-- ------------------------------------------------------------------------- --
-- aiko_gateway.lua
-- ~~~~~~~~~~~~~~~~
-- Please do not remove the following notices.
-- Copyright (c) 2009-2012 by Geekscape Pty. Ltd.
-- Documentation:  http://groups.google.com/group/aiko-platform
-- License: AGPLv3 http://geekscape.org/static/aiko_license.html
-- Version: 0.4 (boonie)
-- ------------------------------------------------------------------------- --
-- See Google Docs: "Project: Aiko: Stream protocol specification"
-- Currently requires an Aiko Gateway (indirect mode only).
-- ------------------------------------------------------------------------- --
-- Custom configuration: See "aiko_configuration.lua".
--
-- ToDo
-- ~~~~
-- - None, yet.
-- ------------------------------------------------------------------------- --

local MQTT
local mqtt_client

function current_directory()
  return(os.getenv("PWD"))
end

-- ------------------------------------------------------------------------- --

function is_production()
-- TODO: Use an environment variable to specify deployment type.

  return(os.getenv("USER") == "root") -- Assume logged in as "root" on OpenWRT
end

-- ------------------------------------------------------------------------- --

function send_message(topic, payload)
  if (mqtt_client.connected == false) then
    mqtt_client:connect("aiko_gateway")
  end

  if (mqtt_client.connected) then
    if (debug) then print("-- send_message(): " .. topic .. ": " .. payload) end

    mqtt_client:publish(topic, payload)
  else
    socket.sleep(10)  -- seconds
  end
end

-- ------------------------------------------------------------------------- --

function send_event_boot(node_name)
  if (debug) then print("-- send_event_boot(): " .. node_name) end

  payload = "(status boot 0.4)"
  send_message("boonie/health/gateway", payload)
end

-- ------------------------------------------------------------------------- --

function send_event_heartbeat(node_name)
  if (debug) then print("-- send_event_heartbeat(): " .. node_name) end

  payload = "(status heartbeat)"
  send_message("boonie/health/gateway", payload)
end

-- ------------------------------------------------------------------------- --

function heartbeat_handler()
  local throttle_counter = 1 -- Always start with a heartbeat

  while (true) do
    throttle_counter = throttle_counter - 1

    if (throttle_counter <= 0) then
      throttle_counter = heartbeat_rate

      send_event_heartbeat(aiko_gateway_name)
    end

    coroutine.yield()
  end
end

-- ------------------------------------------------------------------------- --

function serial_handler()
  serial_client = socket.connect(ser2net_address, ser2net_port)
  serial_client:settimeout(serial_timeout_period)  -- 0 --> non-blocking read

--serial_client:send("")

  local stream, status, partial

  while (status ~= "closed") do
    stream, status, partial = serial_client:receive(16768)  -- (1024)

    if (debug) then
      if (status == "timeout") then
        print("Aiko status: bytes received: ", partial:len())
      else
        print("Aiko status: ", status)
      end
    end
--[[
    print ("Aiko stream:  ", stream)  -- TODO: if not "nil" then catenate
    print ("Aiko partial: ", partial) -- TODO: if not "nil" then got everything
]]
    if (partial ~= nil and partial:len() > 0) then
      parse_message(partial)
    end

    if (status == "timeout") then
      coroutine.yield()
    end
  end

  serial_client:close()
end

-- ------------------------------------------------------------------------- --

function parse_message(buffer)
  if (debug) then print("-- parse_message(): start") end

-- Parse individual Aiko-Node messages, delimited by "carriage return"
  for message in buffer:gmatch("[^\r\n]+") do

-- Check message properly framed, e.g. (message)
    if (message:sub(1, 1) ~= "("  or  message:sub(-1) ~= ")") then
--    print("-- parse_message(): ERROR: Message not delimited by ()")
      if (debug) then print("-- message: ", message) end
    else
      send_message("boonie/telemetry/raw", message)
    end
  end

  if (debug) then print("-- parse_message(): end") end
end

-- ------------------------------------------------------------------------- --

function initialize()
  PLAIN = 1  -- string.find() pattern matching off

  mqtt_client = MQTT.client.create(mqtt_address, 1883)
end

-- ------------------------------------------------------------------------- --

print("[Aiko-Gateway V0.4 2012-05-21]")

if (not is_production()) then require("luarocks.require") end
require("socket")
require("io")
require("ltn12")
MQTT = require("mqtt_library")

require("aiko_configuration")  -- Aiko-Gateway configuration file

initialize()

-- TODO: Keep retrying boot message until success (OpenWRT boot sequence issue)
--send_event_boot(aiko_gateway_name)

coroutine_heartbeat = coroutine.create(heartbeat_handler)

-- TODO: Handle incorrect serial host_name, e.g. not localhost -> fail !

while true do
  coroutine_serial = coroutine.create(serial_handler)

  while (coroutine.status(coroutine_serial)) ~= "dead" do
--  if (debug) then print("-- coroutine.resume(coroutine_heartbeat):") end
--  coroutine.resume(coroutine_heartbeat)

    if (debug) then print("-- coroutine.resume(coroutine_serial):") end
    coroutine.resume(coroutine_serial)
  end

  socket.sleep(10)  -- seconds
end
