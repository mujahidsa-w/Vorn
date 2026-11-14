// VORN authoritative match service for Nakama JavaScript runtime.
// This service owns match membership and validates basic player-state messages.
// It is not a replacement for server-side 3D hit detection yet; that requires
// porting VORN's weapon/raycast rules into a headless authoritative simulation.

var MODULE = "vorn_match";
var MAX_PLAYERS = 10;
var TICK_RATE = 20;
var OP = { PLAYER_STATE: 1, SHOT_INTENT: 2, MATCH_EVENT: 3, SNAPSHOT: 4 };

function safeNumber(v, min, max) {
  return typeof v === "number" && isFinite(v) && v >= min && v <= max;
}

function matchInit(ctx, logger, nk, params) {
  var initialPlayers = {};
  var invited = {};
  if (params && Array.isArray(params.invited)) {
    params.invited.forEach(function (entry) {
      if (entry && entry.presence && entry.presence.userId) invited[entry.presence.userId] = true;
    });
  }
  return {
    state: {
      presences: {},
      invited: invited,
      reservations: {},
      playerStates: initialPlayers,
      maxPlayers: MAX_PLAYERS,
      createdAt: Date.now(),
      emptyTicks: 0,
      tick: 0
    },
    tickRate: TICK_RATE,
    label: JSON.stringify({ mode: "vorn_5v5", open: true, players: 0, max: MAX_PLAYERS })
  };
}

function matchJoinAttempt(ctx, logger, nk, dispatcher, tick, state, presence, metadata) {
  var count = Object.keys(state.presences).length;
  var alreadyPresent = !!state.presences[presence.sessionId];
  var invited = !!state.invited[presence.userId] || !!state.reservations[presence.userId];
  // Allow late joiners while the match has a free slot. A full match is rejected.
  if (!alreadyPresent && count >= MAX_PLAYERS) {
    return { state: state, accept: false, rejectMessage: "VORN match is full (10/10)." };
  }
  // New users must have arrived through the server-side matchmaking result.
  if (!alreadyPresent && !invited) {
    return { state: state, accept: false, rejectMessage: "Join through VORN matchmaking." };
  }
  return { state: state, accept: true };
}

function matchJoin(ctx, logger, nk, dispatcher, tick, state, presences) {
  presences.forEach(function (p) {
    state.presences[p.sessionId] = p;
    state.playerStates[p.sessionId] = {
      userId: p.userId,
      username: p.username || "Player",
      x: 0, y: 0, z: 0,
      yaw: 0, pitch: 0,
      hp: 100, alive: true,
      weapon: "knife",
      lastStateAt: Date.now(),
      lastShotAt: 0
    };
    state.invited[p.userId] = true;
    delete state.reservations[p.userId];
  });
  var count = Object.keys(state.presences).length;
  dispatcher.broadcastMessage(OP.MATCH_EVENT, JSON.stringify({ event: "roster", players: count, maxPlayers: MAX_PLAYERS }), null, null, true);
  return { state: state };
}

function matchLeave(ctx, logger, nk, dispatcher, tick, state, presences) {
  presences.forEach(function (p) {
    delete state.presences[p.sessionId];
    delete state.playerStates[p.sessionId];
  });
  var count = Object.keys(state.presences).length;
  dispatcher.broadcastMessage(OP.MATCH_EVENT, JSON.stringify({ event: "roster", players: count, maxPlayers: MAX_PLAYERS }), null, null, true);
  return { state: state };
}

function matchLoop(ctx, logger, nk, dispatcher, tick, state, messages) {
  state.tick = tick;
  var changed = false;
  messages.forEach(function (message) {
    var sender = message.sender;
    if (!sender || !state.presences[sender.sessionId]) return;
    var player = state.playerStates[sender.sessionId];
    if (!player) return;

    if (message.opCode === OP.PLAYER_STATE) {
      var payload;
      try { payload = JSON.parse(nk.binaryToString(message.data)); } catch (e) { return; }
      if (!payload || !safeNumber(payload.x, -5000, 5000) || !safeNumber(payload.y, -500, 500) || !safeNumber(payload.z, -5000, 5000) || !safeNumber(payload.yaw, -1000, 1000) || !safeNumber(payload.pitch, -1000, 1000)) return;
      // Server owns HP/alive. Clients cannot submit either field.
      player.x = payload.x; player.y = payload.y; player.z = payload.z;
      player.yaw = payload.yaw; player.pitch = payload.pitch;
      if (typeof payload.weapon === "string" && payload.weapon.length <= 24) player.weapon = payload.weapon;
      player.lastStateAt = Date.now();
      changed = true;
    } else if (message.opCode === OP.SHOT_INTENT) {
      // Rate-limit shot requests. Damage is deliberately NOT awarded here until
      // server-side VORN raycasts and weapon inventory are ported.
      var now = Date.now();
      if (now - player.lastShotAt < 35) return;
      player.lastShotAt = now;
      dispatcher.broadcastMessage(OP.SHOT_INTENT, message.data, null, sender, false);
    }
  });

  if (changed || tick % 2 === 0) {
    var snapshot = { tick: tick, players: state.playerStates };
    dispatcher.broadcastMessage(OP.SNAPSHOT, JSON.stringify(snapshot), null, null, false);
  }
  if (Object.keys(state.presences).length === 0) state.emptyTicks++; else state.emptyTicks = 0;
  if (state.emptyTicks > TICK_RATE * 30) return null;
  return { state: state };
}

function matchTerminate(ctx, logger, nk, dispatcher, tick, state, graceSeconds) {
  logger.info("VORN match terminated at tick %d", tick);
  return { state: state };
}

function matchSignal(ctx, logger, nk, dispatcher, tick, state, data) {
  try {
    var reservation = JSON.parse(data);
    if (reservation && Array.isArray(reservation.userIds)) {
      reservation.userIds.forEach(function (userId) {
        if (typeof userId === "string") state.reservations[userId] = true;
      });
    }
  } catch (e) {
    logger.warn("Invalid VORN match reservation signal: %s", e);
  }
  return { state: state, data: "ok" };
}

function matchmakerMatched(ctx, logger, nk, matches) {
  // Reuse an open VORN room if possible so players arriving later can fill it.
  // MatchJoinAttempt enforces the hard 10-player cap.
  try {
    var openMatches = nk.matchList(50, true, "", 1, MAX_PLAYERS - 1);
    if (openMatches && openMatches.length) {
      for (var i = 0; i < openMatches.length; i++) {
        var candidate = openMatches[i];
        if (candidate && candidate.matchId && candidate.size + matches.length <= MAX_PLAYERS) {
          var userIds = matches.map(function (entry) { return entry.presence.userId; });
          nk.matchSignal(candidate.matchId, JSON.stringify({ userIds: userIds }));
          return candidate.matchId;
        }
      }
    }
  } catch (e) {
    logger.warn("Could not query open VORN matches: %s", e);
  }
  return nk.matchCreate(MODULE, { invited: matches });
}

function InitModule(ctx, logger, nk, initializer) {
  initializer.registerMatch(MODULE, {
    matchInit: matchInit,
    matchJoinAttempt: matchJoinAttempt,
    matchJoin: matchJoin,
    matchLeave: matchLeave,
    matchLoop: matchLoop,
    matchTerminate: matchTerminate,
    matchSignal: matchSignal
  });
  initializer.registerMatchmakerMatched(matchmakerMatched);
  logger.info("VORN Nakama runtime loaded. Max players: %d", MAX_PLAYERS);
}
