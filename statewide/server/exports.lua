exports('getUnit', function(src)
  local p = State.peek(src)
  return p and State.copy(p.unit) or nil
end)

exports('getActiveCharacter', function(src)
  local p = State.peek(src)
  return p and State.copy(p.character) or nil
end)

exports('isOnDuty', function(src)
  local p = State.peek(src)
  return p ~= nil and p.unit ~= nil
end)

exports('isClockedIn', function(src)
  return ClockIn ~= nil and ClockIn.get(src) ~= nil
end)

exports('getPostal', function(src)
  local p = State.peek(src)
  return p and p.labels and p.labels.postal or nil
end)

exports('getLocationLabels', function(src)
  local p = State.peek(src)
  return Pure.locationLabels(p and p.labels)
end)

exports('getSceneMarkers', function()
  return SceneMarkers and State.copy(SceneMarkers.list()) or {}
end)

exports('aop', function()
  return Lifecycle.aop
end)
