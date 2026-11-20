local _, ns = ...

-- The group a table needs (engine.needsGroup, extension "party"; Death Roll):
-- the server rolls of the players must reach each other in chat. Only the host
-- invites, only the players seated at its table, at most once per name per
-- GROUP_INVITE_GAP s: after every sit and at every start. It never leaves,
-- disbands or converts a group; when it cannot invite (in a group it does not
-- lead, or a party with no room) it says why in `partyWhy`. A seated player
-- accepts a group invite automatically only from the host of his table
-- (Party.inviteFrom, for wow/).
--
-- Session fields (local, never sent):
--   partyAsked  name -> env.now() of my last invite (host only)
--   partyWhy    nil | "notleader" | "full": why the host invites nobody
local Party = {}
ns.Party = Party

local C = ns.Const
local Names = ns.Names

-- Seated players other than me, in seat order, whose GUID Presence knows and who
-- are not in my group; {} when my client has no env.group.
function Party.missing(s)
  local client, out = s.client, {}
  local env = client.env
  if not env.group then return out end
  for i = 1, #s.seats do
    local name = s.seats[i]
    if name and name ~= env.me then
      local peer = client.presence:get(name)
      if peer and peer.guid and not env.inGroup(peer.guid) then out[#out + 1] = name end
    end
  end
  return out
end

-- Host of a table that needs a group: invite every player missing from my
-- group (not one asked in the last GROUP_INVITE_GAP s), or set partyWhy.
function Party.ensure(s)
  local env = s.client.env
  if s.role ~= "host" or not s:engine().needsGroup or not env.group or not env.groupInvite then return end
  local g, m = env.group(), Party.missing(s)
  if #m == 0 then
    s.partyWhy = nil
  elseif g.grouped and not g.leader then
    s.partyWhy = "notleader"
  elseif g.grouped and not g.raid and g.size + #m > C.PARTY_SIZE then
    s.partyWhy = "full"
  else
    s.partyWhy = nil
    s.partyAsked = s.partyAsked or {}
    local now = env.now()
    for i = 1, #m do
      local asked = s.partyAsked[m[i]]
      if not asked or now - asked >= C.GROUP_INVITE_GAP then
        s.partyAsked[m[i]] = now
        env.groupInvite(m[i])
      end
    end
  end
end

-- A group invite from `shown` (normalized) is to be accepted: I hold a seat at a
-- table that needs a group and `shown` is its host (not me).
function Party.inviteFrom(client, shown)
  local s = client.session
  if not s or not s.mySeat or s.role == "host" or not s:engine().needsGroup then return false end
  return Names.matches(s.host, shown)
end

ns.Ext.party = {
  applied = function(s, seat, a)
    if seat == 0 and (a.k == "sit" or a.k == "start") then Party.ensure(s) end
  end,
}
