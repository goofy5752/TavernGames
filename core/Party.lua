local _, ns = ...

-- The group a table needs (engine.needsGroup, extension "party"; Death Roll):
-- the server rolls of the players must reach each other in chat. Only the host
-- invites, only the players seated at its table, at most once per name per
-- GROUP_INVITE_GAP s: after every sit and at every start. It never leaves,
-- disbands or converts a group; when it cannot invite (in a group it does not
-- lead, or a party with no room) it says why in `partyWhy`. A player seated at
-- such a table, or sitting down at it, accepts a group invite automatically
-- only from the host of that table (Party.inviteFrom, for wow/).
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

-- A group invite from `shown` (normalized) is to be accepted: it comes from the
-- host (not me) of a table that needs a group, where I hold a seat or asked for
-- one. The host invites before its snapshot reaches me, so my pending SIT counts
-- (client.pending), and so does a watcher's sit request of the last
-- PENDING_SECONDS (session.sitAsked = env.now() of it, set by Session.request).
function Party.inviteFrom(client, shown)
  local s, p = client.session, client.pending
  if s then
    if s.role == "host" or not s:engine().needsGroup then return false end
    local asked = s.sitAsked and client.env.now() - s.sitAsked < C.PENDING_SECONDS
    if not s.mySeat and not asked then return false end
    return Names.matches(s.host, shown)
  end
  if not p or p.kind ~= "SIT" then return false end
  local rec = client.lobby:get(p.tid)
  local engine = rec and ns.Games.engine(rec.game)
  return engine ~= nil and engine.needsGroup == true and Names.matches(p.host, shown)
end

ns.Ext.party = {
  applied = function(s, seat, a)
    if seat == 0 and (a.k == "sit" or a.k == "start") then Party.ensure(s) end
  end,
}
