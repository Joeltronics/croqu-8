pico-8 cartridge // http://www.pico-8.com
version 41
__lua__
-- By Joel Geddert
-- License: CC BY-NC-SA 4.0

--
-- Game core consts
--

DEBUG = true

BALL_R = 2.25
BALL_D = 2 * BALL_R
BALL_D2 = BALL_D*BALL_D

BALL_POLE_D = BALL_R + 0.125
BALL_POLE_D2 = BALL_POLE_D*BALL_POLE_D

MOVING_COOLDOWN_FRAMES = 60
SHOT_POWER_METER_RATE = 1/64
SHOT_POWER_METER_FALL_RATE = -1/32
SHOT_POWER_ERR_OVER = 15/360

ROUGH = 16

WIDTH, HEIGHT = 384 + 2*ROUGH, 192+2*ROUGH

CX = WIDTH \ 2
CY = HEIGHT \ 2

PX = 32
W1X = 64
W2X = 96
W3X = CX - 48
WY = CY - 48

WICKETS = {
	{PX, CY, pole=true},
	{W1X, CY},
	{W2X, CY},
	{W3X, HEIGHT - WY},
	{CX, CY},
	{WIDTH - W3X, HEIGHT - WY},
	{WIDTH - W2X, CY},
	{WIDTH - W1X, CY},
	{WIDTH - PX, CY, pole=true},
	{WIDTH - W1X, CY, reverse=true, hidden=true},
	{WIDTH - W2X, CY, reverse=true, hidden=true},
	{WIDTH - W3X, WY, reverse=true},
	{CX, CY, reverse=true, hidden=true},
	{W3X, WY, reverse=true},
	{W2X, CY, reverse=true, hidden=true},
	{W1X, CY, reverse=true, hidden=true},
	{PX, CY, reverse=true, pole=true, hidden=true},
}
WICKET_COLLISION_POINTS = {}  -- Populated at init

--
-- Physics consts
--

COLLISION_CHECK_DIVISIONS = 4

SHOT_V_MAX = 1.5
SHOT_V_MIN = 0.0625

DRAG = 1 - 1/128
DRAG_ROUGH = 1 - 1/8
V2_STOP_THRESH = 1/1024

VELOCITY_REDUCE_BALL_COLLISION = 1 - 1/64
VELOCITY_REDUCE_POLE_COLLISION = 0.5
VELOCITY_REDUCE_WICKET_COLLISION = 0.25

BALL_STOP_RANDOM_MOVEMENT = 0.25

--
-- Graphics Consts
--

DISPLAY_PALETTE = {
	[13]=-5, -- Indigo --> Jade
	[15]=-4, -- Peach --> Royal Blue
}

STATUS_BAR_WIDTH = 8

ROUGH_FILLP = 0b0101010110101010
ROUGH_COLOR = 0x35

PALETTES = {
	-- main, dark, light
	{[8]=15, [2]=1, [14]=12}, -- Blue
	{[8]=8, [2]=2, [14]=14}, -- Red
	{[8]=0, [2]=1, [14]=5}, -- Black
	{[8]=10, [2]=9, [14]=6}, -- Yellow
	{[8]=11, [2]=3, [14]=6}, -- Green
	{[8]=9, [2]=4, [14]=10}, -- Orange
}

SHOT_POWER_COLORS = {1, 12, 11, 10, 9}

--
-- Globals
--

players = {}
balls = {}

player_idx = nil

camera_x = 64
camera_y = CY

shot_angle = 0
shot_power = 0
shot_power_change = 0
shot_power_over = false

moving_cooldown = 0

last_dv2 = nil

debug_pause_physics = false
debug_no_draw_tops = false
debug_draw_primitives = false
debug_increase_shot_pointer_length = false

--
-- Utility functions
--

function print_centered(text, x, y, col)
	local t = '' .. text
	print(t, x - 2*#t, y, col)
end

function round(val)
	return flr(val + 0.5)
end

function line_round(x1, y1, x2, y2, col)
	line(round(x1), round(y1), round(x2), round(y2), col)
end

function clip_num(val, minval, maxval)
	return max(minval, min(maxval, val))
end

function lerp(a, b, t)
	-- return a + t * (b - a)
	return (1 - t) * a + t * b
end

function sort_z(items)
	-- Bubblesort items by z value, or y value if z is not found
	for idx1 = 1,#items do
		local any_swapped = false
		for idx2 = 1,#items-1 do
			local item1 = items[idx1]
			local item2 = items[idx2]
			if ((item1.z or item1.y) < (item2.z or item2.y)) then
				items[idx1] = item2
				items[idx2] = item1
				any_swapped = true
			end
		end
		if (not any_swapped) return
	end
end

function shot_power_color()
	if (shot_power <= 0) return 0
	if (shot_power_over) return 8
	return SHOT_POWER_COLORS[clip_num(flr(shot_power * #SHOT_POWER_COLORS) + 1, 1, #SHOT_POWER_COLORS)]
end

--
-- Sound
--

function play_sound_launch()
	sfx(clip_num(flr(shot_power * 4), 0, 3))
	sfx(clip_num(7 + flr(shot_power * 4), 7, 10))
end

function play_sound_ball_collision(dv2)
	last_dv2 = dv2
	if dv2 > 0.5 then
		sfx(10)
	elseif dv2 > 0.1 then
		sfx(9)
	elseif dv2 > 0.05 then
		sfx(8)
	else
		sfx(7)
	end
end

function play_sound_wicket_collision(ball, is_pole)
	-- local v2 = ball.vx*ball.vx + ball.vy*ball.vy

	if is_pole then
		sfx(4)
		sfx(5)
	else
		sfx(6)
	end
end

function play_sound_score_wicket()
	-- TODO
end

function play_sound_end_game()
	-- TODO
end

--
-- Physics
--

function dotpart(vx, vy, nx, ny)
	-- From pico pool by nusan (CC4-BY-NC-SA)
	local dot = vx*nx + vy*ny
	vx = vx - dot*nx
	vy = vy - dot*ny
	return vx, vy
end

function ball_overlap(dx, dy)

	-- Prevent overflow
	if (abs(dx) + abs(dy) > 127) return 0, nil

	local d2 = dx*dx + dy*dy

	if (d2 and d2 > BALL_D2) return 0, nil

	local d = sqrt(d2)

	local overlap = max(0, BALL_D + 0.25 - d) / d

	return overlap, d
end

function ball_collisions()
	-- Partially based on pico pool by nusan (CC4-BY-NC-SA)

	local any_collisions, current_player = false, players[player_idx]

	for idx1 = 1, #balls do
		local b1 = balls[idx1]
		for idx2 = idx1+1, #balls do
			local b2 = balls[idx2]

			local dx, dy = b1.x - b2.x, b1.y - b2.y

			if dx == 0 and dy == 0 then
				-- Balls are on exactly the same spot, would get divide by zero
				b1.y -= 0.5
				b2.y += 0.5
				dy = b1.y - b2.y
			end

			-- Prevent overflow
			if (abs(dx) + abs(dy) <= 127) d2 = dx*dx + dy*dy

			overlap, d = ball_overlap(dx, dy)

			if overlap > 0 then
				any_collisions = true

				local push = 0.5 * overlap

				b1.x += dx*push
				b1.y += dy*push
				b2.x -= dx*push
				b2.y -= dy*push

				local coll1 = {x=b2.x, y=b2.y}
				local coll2 = {x=b1.x, y=b1.y}

				if (b1 == current_player.ball or b2 == current_player.ball) current_player_ball_collision()

				-- If no balls are moving, then we can skip this part entirely
				if moving_cooldown > 0 then

					local nx, ny = dy / d, -dx / d

					coll1.nx, coll1.ny = nx, ny
					coll2.nx, coll2.ny = nx, ny

					b1.vx *= VELOCITY_REDUCE_BALL_COLLISION
					b1.vy *= VELOCITY_REDUCE_BALL_COLLISION
					b2.vx *= VELOCITY_REDUCE_BALL_COLLISION
					b2.vy *= VELOCITY_REDUCE_BALL_COLLISION

					local dd1x, dd1y = dotpart(b1.vx, b1.vy, nx, ny)
					local dd2x, dd2y = dotpart(b2.vx, b2.vy, nx, ny)

					play_sound_ball_collision(
						dd1x*dd1x + dd1y*dd1y + dd2x*dd2x + dd2y*dd2y
					)

					b1.vx += -dd1x + dd2x
					b1.vy += -dd1y + dd2y
					b2.vx += -dd2x + dd1x
					b2.vy += -dd2y + dd1y
				end

				add(b1.collisions, coll1)
				add(b2.collisions, coll2)
			end
		end
	end

	return any_collisions
end

function check_wicket_collision(ball, w, dx, dy, d2)
	assert(d2 >= 0, 'd2=' .. d2)

	local d = sqrt(d2)
	local push = max(0, BALL_POLE_D + 0.25 - d) / d

	if (push <= 0) return false

	local coll = {x=w.x, y=w.y}

	ball.x += dx*push
	ball.y += dy*push

	if moving_cooldown > 0 then
		play_sound_wicket_collision(ball, w.pole)

		local nx, ny = dx / d, dy / d
		coll.nx, coll.ny = nx, ny

		assert(
			-1.01 < nx and nx < 1.01 and -1.01 < ny and ny < 1.01,
			'dx=' .. dx ..
			',dy=' .. dy ..
			',d2=' .. d2 ..
			',d=' .. d ..
			',nx=' .. nx ..
			',ny=' .. ny
		)

		local vel_reduce = VELOCITY_REDUCE_WICKET_COLLISION
		if (w.pole) vel_reduce = VELOCITY_REDUCE_POLE_COLLISION

		coll.vx_before, coll.vy_before = ball.vx, ball.vy

		ball.vx *= vel_reduce
		ball.vy *= vel_reduce

		local vx, vy = ball.vx, ball.vy
		local v_dot_n = vx * nx + vy * ny

		ball.vx -= 2 * v_dot_n * nx
		ball.vy -= 2 * v_dot_n * ny

		coll.vx_after, coll.vy_after = ball.vx, ball.vy
	end

	add(ball.collisions, coll)

	return true
end

function wicket_collisions()

	local any_collisions = false

	for player in all(players) do
		local ball = player.ball
		if ball then
			for w in all(WICKET_COLLISION_POINTS) do

				local dx, dy, d2 = ball.x - w.x, ball.y - w.y

				if dx == 0 and dy == 0 then
					-- Ball is on exactly the same spot, would get divide by zero
					ball.y += 1
					dy = ball.y - w.y
				end

				if (abs(dx) + abs(dy) <= 127) d2 = dx*dx + dy*dy

				if d2 and d2 <= BALL_POLE_D2 then
					assert(d2 >= 0, 'd2=' .. d2)

					if not w.hidden then
						if (check_wicket_collision(ball, w, dx, dy, d2)) any_collisions = true
					end

					if w.pole and w.idx == player.last_wicket_idx + 1 then
						score_wicket(player)
					end
				end
			end
		end
	end

	return any_collisions
end

function collisions()
	local any_collisions = wicket_collisions()
	any_collisions = ball_collisions() or any_collisions
	return any_collisions
end

function resolve_all_static_collisions()
	for i=1,100 do
		if (not collisions()) return
	end
	assert(false, "resolve_all_static_collisions hit iteration limit")
end

function resolve_all_static_collisions_for_ball(ball)

	local x_orig, y_orig, stuck_counter = ball.x, ball.y, 0

	for i = 1,200 do
		local any_collisions = wicket_collisions()

		-- This logic needs to be slightly different from regular ball collisions
		-- On collision, we only move this ball, not the other
		-- TODO: consolidate?
		for b2 in all(balls) do
			assert(b2)
			if b2 != ball then

				local dx, dy = ball.x - b2.x, ball.y - b2.y

				if dx == 0 and dy == 0 then
					-- Balls are on exactly the same spot, would get divide by zero
					ball.y += 1
					dy = ball.y - b2.y
				end

				local overlap, d = ball_overlap(dx, dy)

				if overlap > 0 then
					any_collisions = true
					add(ball.collisions, {x=b2.x, y=b2.y})
					add(b2.collisions, {x=ball.x, y=ball.y})
					ball.x += dx*overlap
					ball.y += dy*overlap
				end
			end
		end

		if (not any_collisions) return

		if i % 10 == 0 then
			-- If hitting lots of iterations, might be stuck between other balls/objects
			-- Move ball a random distance away from original position, increasing each time
			stuck_counter += 1
			ball.x = x_orig + 2 * stuck_counter * (rnd() - 0.5)
			ball.y = y_orig + 2 * stuck_counter * (rnd() - 0.5)
		end
	end

	assert(false, "resolve_all_static_collisions_for_ball hit iteration limit")
end

--
-- Game logic
--

function reset_off_screen_balls()
	for ball in all(balls) do
		local x_was, y_was = ball.x, ball.y
		ball.x = clip_num(ball.x, ROUGH, WIDTH-ROUGH-1)
		ball.y = clip_num(ball.y, ROUGH, HEIGHT-ROUGH-1)
		if (ball.x != x_was or ball.y != y_was) resolve_all_static_collisions_for_ball(ball)
	end
end

function next_shot_same_player()
	reset_off_screen_balls()
	shot_power = 0
	shot_angle = 0
	shot_power_change = 0
	if (WICKETS[players[player_idx].last_wicket_idx + 1].reverse) shot_angle = 0.5
end

function next_player()

	local player

	if player_idx then
		player = players[player_idx]
		player.shots = 0
		if (player.bonus_shots) player.bonus_shots = 0
	else
		player_idx = 0
	end

	player_idx %= #PALETTES
	player_idx += 1
	player = players[player_idx]

	next_shot_same_player()

	assert(player.shots == 0, 'player.shots='..player.shots)
	assert((not player.bonus_shots) or (player.bonus_shots == 0), 'player.bonus_shots='..(player.bonus_shots or 'nil'))
	player.shots = 1

	if (not player.ball) reset_ball(player)

	camera_x = player.ball.x
	camera_y = player.ball.y
end

function current_player_ball_collision()
	local p = players[player_idx]
	p.bonus_shots = p.bonus_shots or 2
end

function score_wicket(player)
	if player.last_wicket_idx == #WICKETS then
		play_sound_end_game()
		-- TODO: finish game
	else
		play_sound_score_wicket()
		player.last_wicket_idx += 1
		if (player == players[player_idx]) player.shots += 1
		player.bonus_shots = nil
	end
end

function reset_ball(player)
	local palette = player.palette

	player.ball = {
		x=WICKETS[1][1] + 4,
		y=WICKETS[1][2] + 5,
		vx=0,
		vy=0,
		color=palette[8],
		palette=palette,
		last_wicket_idx=1,
		collisions={},
	}

	balls = {}
	for p in all(players) do
		if (p.ball) add(balls, p.ball)
	end

	resolve_all_static_collisions_for_ball(player.ball)
end

function add_wicket_collision_points(idx, wicket)
	if wicket.pole then
		add(WICKET_COLLISION_POINTS, { x=wicket[1], y=wicket[2] - 1, idx=idx, pole=true, hidden=wicket.hidden })
	else
		add(WICKET_COLLISION_POINTS, { x=wicket[1], y=wicket[2] - 5, idx=idx, hidden=wicket.hidden })
		add(WICKET_COLLISION_POINTS, { x=wicket[1], y=wicket[2] + 4, idx=idx, hidden=wicket.hidden })
	end
end

function _init()
	players, balls, WICKET_COLLISION_POINTS = {}, {}, {}

	-- Add hidden wickets first
	for idx = 1,#WICKETS do
		local wicket = WICKETS[idx]
		if (wicket.hidden) add_wicket_collision_points(idx, wicket)
	end
	for idx = 1,#WICKETS do
		local wicket = WICKETS[idx]
		if (not wicket.hidden) add_wicket_collision_points(idx, wicket)
	end

	for palette in all(PALETTES) do
		add(players, {
			palette=palette,
			color_main=palette[8],
			color_light=palette[14],
			color_dark=palette[2],
			last_wicket_idx=1,
			shots=0,
			-- bonus_shots=nil,
		})
	end

	player_idx = nil
	next_player()

	cls()
	if (DEBUG) poke(0x5F2D, 1)  -- enable keyboard
	poke(0x5f36, 0x40)  -- prevent printing at bottom of screen from triggering scroll
end

function check_wickets(player)
	-- Note: only checks wickets, not poles
	-- (Poles are handled through collision physics)

	local w, ball = WICKETS[player.last_wicket_idx + 1], player.ball
	if (w.pole or not ball) return
	local x, y, xp, yp, wx, wy = ball.x, ball.y, ball.x_prev, ball.y_prev, w[1], w[2]

	local through = false
	if wy - 5 <= y and y <= wy + 4 then
		if x == wx then
			-- In case ball is stopped exactly on wicket
			-- (Could handle this with conditions below, but this is more mistake-proof)
			-- FIXME: technically this could trigger a wicket when going the wrong direction
			through = true
		elseif w.reverse then
			if (xp >= wx and x < wx) through = true
		else
			if (xp <= wx and x > wx) through = true
		end
	end
	if (through) score_wicket(player)
end

function launch_ball()

	if shot_power_over then
		-- Add error
		local angle_rand = rnd() - 0.5
		-- Range is [0.5, 0.5)
		if (abs(angle_rand) < 0.25) angle_rand *= 2
		-- Range is still [0.5, 0.5), but biased away from center
		angle_rand *= 2 * SHOT_POWER_ERR_OVER
		-- Range is [-SHOT_POWER_ERR_OVER, SHOT_POWER_ERR_OVER), biased away from center
		shot_angle += angle_rand
	end

	shot_angle = round((shot_angle * 256) % 256) / 256

	local player = players[player_idx]
	local dx, dy = cos(shot_angle), sin(shot_angle)
	local v = SHOT_V_MIN + (SHOT_V_MAX - SHOT_V_MIN) * shot_power * shot_power

	player.ball.vx = v * dx
	player.ball.vy = v * dy
	moving_cooldown = MOVING_COOLDOWN_FRAMES

	if player.bonus_shots and player.bonus_shots > 0 then
		player.bonus_shots -= 1
	else
		player.shots -= 1
	end

	play_sound_launch()
end

function _update60()

	local player = players[player_idx]
	local player_ball, op, x = player.ball, btnp(4), btn(5)

	if DEBUG then
		while stat(30) do
			local key = stat(31)
			if (key == '1') debug_draw_primitives = not debug_draw_primitives
			if (key == '2') debug_increase_shot_pointer_length = not debug_increase_shot_pointer_length
			if (key == '3') debug_no_draw_tops = not debug_no_draw_tops
			if (key == '=') debug_pause_physics = not debug_pause_physics
			if (key == '7') player.bonus_shots = nil
			if (key == '8') player.bonus_shots = 0
			if (key == '9') player.bonus_shots = 1
			if (key == '0') player.bonus_shots = 2
			if (key == ']') next_player()

			if moving_cooldown <= 0 then

				local moved = false

				if key == 'h' then
					player_ball.x -= 1
					moved = true
				elseif key == 'j' then
					player_ball.y += 1
					moved = true
				elseif key == 'k' then
					player_ball.y -= 1
					moved = true
				elseif key == 'l' then
					player_ball.x += 1
					moved = true
				end

				if (moved) resolve_all_static_collisions_for_ball(player_ball)
			end
		end
	end

	if moving_cooldown <= 0 then

		if op then
			if shot_power_change > 0 then
				-- Shot power meter rising
				launch_ball()
				shot_power_change = 0
			elseif shot_power_change < 0 then
				-- Shot power meter falling
				launch_ball()
				shot_power_change = 0
			else
				-- Shot power = 0, start shot power meter
				shot_power_change = SHOT_POWER_METER_RATE
			end

			if shot_power_change == 0 then
				-- Re-enable key repeat
				poke(0x5f5c, 0)
				poke(0x5f5d, 0)
			else
				-- Disable key repeat
				poke(0x5f5c, 255)
				poke(0x5f5d, 255)
			end
		end

		shot_power += shot_power_change

		if shot_power >= 1 then
			shot_power_change = SHOT_POWER_METER_FALL_RATE
			shot_power_over = true
		elseif shot_power <= 0 then
			shot_power_change = 0
			shot_power_over = false
		end

		shot_power = clip_num(shot_power, 0, 1)
	end

	for ball in all(balls) do
		ball.collisions = {}
	end

	if moving_cooldown > 0 then

		if (not debug_pause_physics) or op then

			-- Process physics

			moving_cooldown -= 1

			-- TODO optimization: keep a list of moving players, only iterate those
			-- TODO optimization: when looping through each ball, make a list of close players & wickets
			-- (with simpler check, e.g. abs(dx)+abs(dy)), then these are the only ones that get checked for collisions

			for ball in all(balls) do
				ball.x_prev = ball.x
				ball.y_prev = ball.y
			end

			for idx=1,COLLISION_CHECK_DIVISIONS do
				for ball in all(balls) do
					if ball.vx != 0 or ball.vy != 0 then
						ball.x += ball.vx / COLLISION_CHECK_DIVISIONS
						ball.y += ball.vy / COLLISION_CHECK_DIVISIONS
					end
				end
				if (collisions()) moving_cooldown = MOVING_COOLDOWN_FRAMES
			end

			for ball in all(balls) do
				if ball.vx != 0 or ball.vy != 0 then

					local drag = DRAG
					if (ball.x < ROUGH or ball.y < ROUGH or ball.x >= WIDTH-ROUGH or ball.y >= HEIGHT-ROUGH) drag = DRAG_ROUGH

					ball.vx *= drag
					ball.vy *= drag

					local v2 = ball.vx*ball.vx + ball.vy*ball.vy
					if (v2 <= V2_STOP_THRESH) then
						-- Stop ball

						-- Move ball slightly when it stops
						-- TODO: Add ball spin, and make this depend on it
						ball.x = round(ball.x + rnd(2*BALL_STOP_RANDOM_MOVEMENT) - BALL_STOP_RANDOM_MOVEMENT)
						ball.y = round(ball.y + rnd(2*BALL_STOP_RANDOM_MOVEMENT) - BALL_STOP_RANDOM_MOVEMENT)
						ball.vx, ball.vy = 0, 0
					end
					moving_cooldown = MOVING_COOLDOWN_FRAMES
				end
			end
		end

		for player in all(players) do
			check_wickets(player)
		end

		-- TODO: If player's ball isn't moving but another is, make camera follow that one instead
		camera_x = player_ball.x
		camera_y = player_ball.y

		if moving_cooldown <= 0 then
			if (player.shots + (player.bonus_shots or 0)) <= 0 then
				next_player()
			else
				next_shot_same_player()
			end
		end

	else
		if x then
			if (btn(0)) camera_x -= 4  -- left
			if (btn(1)) camera_x += 4  -- right
			if (btn(2)) camera_y -= 4  -- up
			if (btn(3)) camera_y += 4  -- down
		else
			camera_x = player.ball.x
			camera_y = player.ball.y
			if shot_power_change == 0 then
				if (btn(0)) shot_angle += 1/256  -- left
				if (btn(1)) shot_angle -= 1/256  -- right
			end
		end

		shot_angle = round((shot_angle * 256) % 256) / 256
	end

	moving_cooldown = max(moving_cooldown, 0)
	camera_x = clip_num(camera_x, 64 - STATUS_BAR_WIDTH, WIDTH-64)
	camera_y = clip_num(camera_y, 64, HEIGHT-64)

	cpu_update = stat(1)
end

function draw_shot()
	local player = players[player_idx]
	local x, y = player.ball.x, player.ball.y
	if (not x) return -- HACK: this shouldn't be needed
	local dx, dy = cos(shot_angle), sin(shot_angle)

	-- Draw line

	local l = 24
	if (debug_increase_shot_pointer_length) l = 256

	line_round(x, y, x + l*dx, y + l*dy, shot_power_color())

	-- Draw club

	-- TODO: There can still sometimes be small gaps in this, figure out a better way to draw it
	-- (Use a sprite rotation algo?)

	local w, l, d = 1.5, 10, 4 + 5*shot_power

	local c = {
		{ w*dy - d*dx,     -w*dx - d*dy},
		{ w*dy - (d+l)*dx, -w*dx - (d+l)*dy},
		{-w*dy - (d+l)*dx,  w*dx - (d+l)*dy},
		{-w*dy - d*dx,      w*dx - d*dy},
	}

	for i=1,4 do
		c[i][1] = round(x + c[i][1])
		c[i][2] = round(y + c[i][2])
	end

	for i=0,3 do
		line_round(
			lerp(c[1][1], c[4][1], i/4), lerp(c[1][2], c[4][2], i/4),
			c[2][1], c[2][2],
			4)

		line_round(
			lerp(c[3][1], c[2][1], i/4), lerp(c[3][2], c[2][2], i/4),
			c[4][1], c[4][2],
			4)
	end
	line(c[1][1], c[1][2], c[4][1], c[4][2], 5)
	line(c[2][1], c[2][2], c[3][1], c[3][2], 5)

	for i in all({1, 4}) do
	line_round(
		lerp(c[1][1], c[2][1], i/5), lerp(c[1][2], c[2][2], i/5),
		lerp(c[4][1], c[3][1], i/5), lerp(c[4][2], c[3][2], i/5),
		player.color_main)
	end
end

function draw_status_bar()

	rectfill(1, 1, STATUS_BAR_WIDTH - 1, 128, 4)
	line(STATUS_BAR_WIDTH, 1, STATUS_BAR_WIDTH, 128, 2)
	line(0, 1, 0, 128, 9)
	line(0, 0, STATUS_BAR_WIDTH, 0, 9)
	pset(STATUS_BAR_WIDTH, 0, 4)
	pset(0, 0, 6)

	for idx = 1,#players do
		local p = players[idx]

		local main_color, textcol = p.color_main, 7
		if (p.color_main >= 9) textcol = 0

		local y1 = 9*idx-1
		local y2 = y1 + 6

		rectfill(1, y1, STATUS_BAR_WIDTH-1, y2, main_color)
		line(0, y1, 0, y2, p.color_light)
		line(STATUS_BAR_WIDTH, y1, STATUS_BAR_WIDTH, y2, p.color_dark)

		print_centered(players[idx].last_wicket_idx - 1, 5, y1+1, textcol)

		if idx == player_idx then

			local x = STATUS_BAR_WIDTH + 4

			pal(p.ball.palette)
			for i = 1,p.shots do
				spr(1, x-3, y1)
				x += 6
			end
			pal()

			if p.bonus_shots then
				for i=1,2 do
					if (i <= p.bonus_shots) then
						pal(p.ball.palette)
						spr(1, x-3, y1)
						pal()
						circ(x, y1 + 3, 2, textcol)
					else
						circ(x, y1 + 3, 2, textcol)
					end
					x += 6
				end
			end
		end
	end

	if shot_power > 0 or shot_power_change != 0 then
		-- Shot power meter
		local col = shot_power_color()
		local y = 125 - 60*shot_power
		rectfill(3, y, 5, 127, col)
		rect(2, 64, 6, 128, 0)
		print('◀', STATUS_BAR_WIDTH - 1, y-2, col)
	end

	if (not debug_draw_primitives) spr(54, 0, 124, 2, 1)
end

function _draw()

	local player, sprites, x, y = players[player_idx], {}
	local next_wicket = WICKETS[player.last_wicket_idx + 1]

	camera(round(camera_x - 64), round(camera_y - 64))

	--
	-- Field
	--

	for y=0,ceil((HEIGHT-2*ROUGH)/16) do
		for x=0,ceil((WIDTH-2*ROUGH)/16) do
			local fp = 0b0101101001011010
			if (x % 2 == 0 and y % 2 == 0) fp = 0x0000
			if (x % 2 == 1 and y % 2 == 1) fp = 0xFFFF
			fillp(fp)
			local off = ROUGH
			if (ROUGH < 1) off = -8
			rectfill(x*16 + off, y*16 + off, x*16 + 16 + off, y*16 + 16 + off, 0xD3)
		end
	end
	if ROUGH > 0 then
		fillp(ROUGH_FILLP)
		rectfill(0, 0, WIDTH, ROUGH-1, ROUGH_COLOR)
		rectfill(0, HEIGHT - ROUGH, WIDTH, HEIGHT, ROUGH_COLOR)
		rectfill(0, ROUGH, ROUGH, HEIGHT - ROUGH, ROUGH_COLOR)
		rectfill(WIDTH - ROUGH, ROUGH, WIDTH, HEIGHT - ROUGH, ROUGH_COLOR)
	end
	fillp()

	-- Boundary
	if (ROUGH < 1) rect(0, 0, WIDTH - 1, HEIGHT - 1, 7)

	--
	-- Bases & shadows
	--

	-- Draw ball shadows
	if not debug_draw_primitives then
		for ball in all(balls) do
			spr(2, round(ball.x) - 2, round(ball.y) - 4)
		end
	end

	-- Draw wicket & pole bases
	if not debug_draw_primitives then
		palt(0, false)
		palt(3, true)
		for w in all(WICKETS) do
			if not w.hidden then
				if w.pole then
					spr(39, w[1], w[2]-7)
				else
					spr(17, w[1]-1, w[2]-8, 1, 2)
				end
			end
		end
		palt()
	end	

	-- Draw arrow on next wicket

	x, y = next_wicket[1], next_wicket[2] - 3
	if next_wicket.pole then
		x -= 9
		if (next_wicket.reverse) x += 11
		y += 1
	elseif next_wicket.reverse then
		x -= 1
	end
	spr(3, x, y, 1, 1, next_wicket.reverse)

	if (moving_cooldown <= 0) draw_shot()

	--
	-- Balls & wickets - stuff where Z-order matters
	--

	for ball in all(balls) do
		x, y = round(ball.x), round(ball.y)
		if debug_draw_primitives then
			circ(x, y, BALL_R, ball.color)
			pset(x, y, 0)
		else
			local idx = 8 + (round(0.5 * x) % 8) + 16*(round(0.5 * y) % 4)
			-- idx = 1 -- DEBUG
			add(sprites, {idx=idx, x=x - 3, y=y-3, z=y, pal=ball.palette})
		end
	end
	pal()

	if (not debug_no_draw_tops) and (not debug_draw_primitives) then
		for w in all(WICKETS) do
			if not w.hidden then
				if w.pole then
					add(sprites, {idx=23, x=w[1], y=w[2]-7, z=w[2], palt=3})
				else
					add(sprites, {idx=18, x=w[1]-1, y=w[2]-8, z=w[2]-4, palt=3})
					add(sprites, {idx=34, x=w[1]-1, y=w[2], z=w[2]+4, palt=3})
					add(sprites, {idx=35, x=w[1]-1, y=w[2]-8, z=w[2]+20, palt=3}) -- Extra sprite for top
				end
			end
		end
	end

	--
	-- Draw sprites, in Z order
	--

	--[[
	TODO optimizations: (Bubblesort is slow, O(n^2))
	- Do not add offscreen sprites to list
	- Sort list of wickets at init, then they're already sorted
	- Sort list each time we add a sprite
	]]

	sort_z(sprites)

	for s in all(sprites) do
		pal(s.pal)
		if (s.palt) then
			palt(0, false)
			palt(s.palt, true)
		else
			palt()
		end
		spr(s.idx, round(s.x), round(s.y), s.w or 1, s.h or 1)
	end
	palt()
	pal()

	if debug_draw_primitives then
		for ball in all(balls) do
			line_round(
				ball.x,
				ball.y,
				ball.x + 30*ball.vx,
				ball.y + 30*ball.vy,
				11)
		end

		for ball in all(balls) do
			for coll in all(ball.collisions) do

				-- Normal: orange
				if (coll.nx) line_round(ball.x, ball.y, ball.x + 16*coll.nx, ball.y + 16*coll.ny, 9)

				-- v before: blue
				if (coll.vx_before) line_round(ball.x, ball.y, ball.x - 30 * coll.vx_before, ball.y - 30*coll.vy_before, 12)

				-- v after: red
				if (coll.vx_after) line_round(ball.x, ball.y, ball.x + 30 * coll.vx_after, ball.y + 30*coll.vy_after, 8)

				line_round(ball.x, ball.y, coll.x, coll.y, 14)
			end
		end

		for w in all(WICKET_COLLISION_POINTS) do
			local col = 9
			if (w.pole) col = 8
			if (w.hidden) col = 6
			pset(w.x, w.y, col)
		end
	end

	--
	-- HUD
	--

	camera()
	draw_status_bar()

	--
	-- Debug overlays
	--

	if DEBUG then

		if debug_pause_physics then
			print_centered('paused', 64, 0, 8)
		end

		cursor(96, 1, 8)

		-- print('mem:' .. stat(0))
		local cpu = stat(1)
		-- local cpu_draw = cpu - cpu_update
		-- print('cpu:' .. round(cpu * 100) .. '=' .. round(cpu_update * 100) .. '+' .. round(cpu_draw * 100))
		print(round(cpu * 100))

		local player_ball = players[player_idx].ball
		print('x=' .. player_ball.x)
		print('y=' .. player_ball.y)
		if (moving_cooldown <= 0) then
			print('p=' .. shot_power)
			print('a=' .. shot_angle*256)
		else
			print('vx=' .. player_ball.vx)
			print('vy=' .. player_ball.vy)
		end

		if (last_dv2) print('dv2=' .. last_dv2)
	end

	--
	-- Set display palette
	--

	pal(DISPLAY_PALETTE, 1)
end

__gfx__
00000000000000000000000000000000000000003333777777773333f33333330000000000000000000000000000000000000000000000000000000000000000
0000000000e8800000000000000008000000000033337333333733338333333300e6800000ee800000ee800000ee800000e6800000ee800000ee800000ee8000
000000000e7e88000000000000000880000000003333733333373333033333330e8788000e8878000e8888000e7888000e8788000e8878000e8888000e788800
0000000008e888000055550088888888000000003333733333373333a33333330887880008878800067776000887880008878800088788000677760008878800
00000000088882000555555000000880000000003333733555575553b33533330887820008788200088882000888720008878200087882000888820008887200
00000000008220000555555000000800000000003333735333373533935333330086200000822000008220000082200000862000008220000082200000822000
00000000000000000055550000000000000000003333753333375333453333330000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000003333733333373333433333330000000000000000000000000000000000000000000000000000000000000000
33333333333333333333333333333333333333333333777777773333f33333330000000000000000000000000000000000000000000000000000000000000000
733533333333333333373333333333333333333333337333333733338333333300e6800000ee800000ee800000ee800000e6800000ee800000ee800000ee8000
73553333333333333367333333333333333333333333733333373333033333330e7888000e8776000e777800067788000e8878000e8886000e88880006888800
75353333333333333637333333333333333333333333733333373333a33333330878880008788800068886000888780008887800088878000688860008788800
73353333e55555336337333333334333333343333333733333373333b33333330878820006888200088882000888850008887200067782000877720008877200
73353333333335333337333333333533333333333333733333373333933333330086200000822000008220000082200000862000008220000082200000822000
73353333333335333337333333333353333333333333733333373333433333330000000000000000000000000000000000000000000000000000000000000000
73353333333335333337333333333335333333333333733333373333433333330000000000000000000000000000000000000000000000000000000000000000
73353333333335333337333333333333000000003333333333333333333333330000000000000000000000000000000000000000000000000000000000000000
733533333333353333373333333733330000000033333333333333333333333300ee600000ee800000ee800000ee800000ee8000007e80000077600000e76000
63353333333335333337333333373333000000003333333333333333333333330e8887000e8888000e8888000e8888000788880007888800078888000e888600
63533333333335333363333333373333000000003333333333333333333333330888870008888600088888000688880006888800068888000888880008888600
65333333333335333633333333373333000000003333333555555553333333330888860008888600068882000688820006888200088882000888820008888200
63333333e55555336333333333373333000000003333335333333533333333330082200000822000006520000065200000622000008220000082200000822000
33333333333333333333333333373333000000003333353333335333333333330000000000000000000000000000000000000000000000000000000000000000
33333333333333333333333333373333000000003333533333353333e55555530000000000000000000000000000000000000000000000000000000000000000
3333333333333333333333333333333333333333333333330d030030000000000000000000000000000000000000000000000000000000000000000000000000
3333333333333333333333333333333333333333333333333dd3d03d0000000000e6800000ee800000ee800000ee800000e6800000ee800000ee800000ee8000
33333333333333333333333333333333333333333333333353d5d5dd500000000e8878000e8886000e888800068888000e7888000e8776000e77780006778800
333377777777333333337333333733333333777777773333535535d3d00000000888780008887800068886000878880008788800087888000688860008887800
3333353333335333333335333333533333333333333333333d5d3d33d00000000888720006778200087772000887720008788200068882000888820008888200
3333335333333533333333533333353333333333333333335d3d5d35300000000086200000822000008220000082200000862000008220000082200000822000
333333355555555333333335555555533333333333333333535353d5300000000000000000000000000000000000000000000000000000000000000000000000
333333333333333333333333333333333333333333333333355333d3d00000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
910600001863500000036000060001600006000160001600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
490600002463500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
490600003064500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
490600003c64500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
490400001845500405004050040500405004050040500405004050040500405004050040500405004050040500405004050040500405004050040500405004050040500405004050040500405004050040500405
010200003061500605006050060500605006050060500605006050060500605006050060500605006050060500605006050060500605006050060500605006050060500605006050060500605006050060500605
010200003061500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
910400001841500400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400
490400001842500400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400
010600001843500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010a00001845500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
