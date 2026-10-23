-- Make a Bluetooth output the default sink when it connects, as if picked
-- by hand: it goes to the top of the saved history and you can still switch
-- away while it's connected.

log = Log.open_topic ("s-bluetooth-default")

SimpleEventHook {
  name = "mangifera/bluetooth-default",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-added" },
      Constraint { "media.class", "=", "Audio/Sink" },
      Constraint { "device.api", "=", "bluez5" },
    },
  },
  execute = function (event)
    local node = event:get_subject ()
    local name = node.properties ["node.name"]
    local om = event:get_source ():call ("get-object-manager", "metadata")
    local metadata = om:lookup { Constraint { "metadata.name", "=", "default" } }
    if metadata == nil or name == nil then
      return
    end

    log:info ("bluetooth output added, making it the default: " .. name)
    metadata:set (0, "default.configured.audio.sink", "Spa:String:JSON",
        Json.Object { ["name"] = name }:to_string ())
  end
}:register ()
