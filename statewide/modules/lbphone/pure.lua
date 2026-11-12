LbPhonePure = {}

local PHONE_MAX = 20

function LbPhonePure.company(companies, name)
  if type(companies) ~= 'table' or type(name) ~= 'string' then return nil end
  local label = companies[name]
  if label == nil or label == false then return nil end
  return name
end

function LbPhonePure.text(value, max)
  if type(value) ~= 'string' then return nil end
  local spaced = value:gsub('%c', ' '):gsub('%s+', ' ')
  return Pure.clean(spaced, max)
end

function LbPhonePure.describe(company, value, max)
  local text = LbPhonePure.text(value, max)
  if not text then return nil end
  return ('[TEXT %s] %s'):format(company, text)
end

function LbPhonePure.location(labels, postal, unknown)
  local street = type(labels) == 'table' and Pure.locationText(labels) or nil
  if street then return street end
  if type(postal) == 'string' and postal ~= '' then return ('Near postal %s'):format(postal) end
  return unknown
end

function LbPhonePure.noteGate(entry, now, cooldown, max)
  entry.count = entry.count or 0
  if entry.count >= max then
    if entry.told then return 'silent' end
    entry.told = true
    return 'capped'
  end
  if entry.last and now - entry.last < cooldown then return 'cooldown' end
  entry.last = now
  entry.count = entry.count + 1
  return 'ok'
end

function LbPhonePure.phone(value)
  if type(value) == 'number' then value = tostring(math.tointeger(value) or value) end
  if type(value) ~= 'string' then return nil end
  value = value:match('^%s*(.-)%s*$')
  if value == '' or #value > PHONE_MAX or not value:match('^[%d %(%)%+%-]+$') or not value:find('%d') then return nil end
  return value
end

function LbPhonePure.point(v)
  local kind = type(v)
  if kind ~= 'table' and kind ~= 'userdata' and kind ~= 'vector3' and kind ~= 'vector2' and kind ~= 'vector4' then return nil end
  local ok, x, y = pcall(function() return v.x, v.y end)
  if not ok or type(x) ~= 'number' or type(y) ~= 'number' then
    if kind ~= 'table' then return nil end
    x, y = v[1], v[2]
  end
  if type(x) ~= 'number' or type(y) ~= 'number' then return nil end
  return Pure.position({ x = x, y = y })
end

LbPhonePure.INPUT_MAX = 2000
LbPhonePure.TAG_REACH = 500.0

function LbPhonePure.sharedLocation(value)
  if type(value) ~= 'string' then return value, nil end
  if #value > LbPhonePure.INPUT_MAX then value = value:sub(1, LbPhonePure.INPUT_MAX) end
  local at
  local rest = value:gsub('<!SENT%-LOCATION%-([^!]*)!>', function(inner)
    if not at then
      local x, y = inner:match('^X=([%d%.%-eE+]+)Y=([%d%.%-eE+]+)$')
      at = Pure.position({ x = tonumber(x), y = tonumber(y) })
    end
    return ' '
  end)
  rest = rest:gsub('<![^>]*$', '')
  return rest, at
end

function LbPhonePure.placeFor(read, tagged)
  if not read or not tagged then return read or tagged end
  local dx, dy = tagged.x - read.x, tagged.y - read.y
  if dx * dx + dy * dy <= LbPhonePure.TAG_REACH * LbPhonePure.TAG_REACH then return tagged end
  return read
end

local ICONS = { attached = 'warning', panic = 'danger' }

function LbPhonePure.officerNotice(kind, payload, labels)
  local icon = ICONS[kind]
  if not icon or type(payload) ~= 'table' then return nil end
  local content
  if kind == 'panic' then
    content = Pure.joinParts(' · ', payload.callNumber, payload.postal)
  else
    content = Pure.joinParts(' · ', payload.number, payload.nature, payload.postal)
  end
  if content == '' then content = labels[kind] end
  return { title = labels[kind], content = content, icon = icon }
end

function LbPhonePure.newBook(max)
  return { max = max, order = {}, entries = {} }
end

function LbPhonePure.remember(book, number, entry)
  if book.entries[number] == nil then book.order[#book.order + 1] = number end
  book.entries[number] = entry
  while #book.order > book.max do
    local oldest = table.remove(book.order, 1)
    book.entries[oldest] = nil
  end
end

function LbPhonePure.recall(book, number)
  return number and book.entries[number] or nil
end

function LbPhonePure.forget(book, number)
  if book.entries[number] == nil then return end
  book.entries[number] = nil
  for i = 1, #book.order do
    if book.order[i] == number then
      table.remove(book.order, i)
      return
    end
  end
end

return LbPhonePure
