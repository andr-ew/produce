local Produce = { grid = {} }

-- integer_trigger. incriment & decriment an integer by triggering two keys
do
    local defaults = {
        state = {1},
        x = 1,                      --x position of the component
        y = 1,                      --y position of the component
        edge = 'rising',            --input edge sensitivity. 'rising' or 'falling'.
        x_next = 1,                 --x position of a key that incriments value
        y_next = 1,                 --y position of a key that incriments value
        x_prev = nil,               --x position of a key that decriments value. nil for no dec
        y_prev = nil,               --y position of a key that decriments value. nil for no dec
        t = 0.1,                    --trigger time
        levels = { 0, 15 },         --brightness levels. expects a table of 2 ints 0-15
        wrap = true,                --wrap value around min/max
        min = 1,                    --min value
        max = 4,                    --max value
        input = function(n, z) end, --input callback, passes last key state on any input
    }
    defaults.__index = defaults

    function Produce.grid.integer_trigger()
        local clk = {}
        local blink = { 0, 0 }

        return function(props)
            if crops.device == 'grid' then 
                setmetatable(props, defaults) 

                if crops.mode == 'input' then 
                    local x, y, z = table.unpack(crops.args) 
                    local nxt = x == props.x_next and y == props.y_next
                    local prev = x == props.x_prev and y == props.y_prev

                    if nxt or prev then
                        if
                            (z == 1 and props.edge == 'rising')
                            or (z == 0 and props.edge == 'falling')
                        then
                            local old = crops.get_state(props.state) or 0
                            local v = old + (nxt and 1 or -1)

                            if props.wrap then
                                while v > props.max do v = v - (props.max - props.min + 1) end
                                while v < props.min do v = v + (props.max - props.min + 1) end
                            end
         
                            v = util.clamp(v, props.min, props.max)
                            if old ~= v then
                                crops.set_state(props.state, v)
                            end
                        end
                        do
                            local i = nxt and 2 or 1

                            if clk[i] then clock.cancel(clk[i]) end

                            blink[i] = 1

                            clk[i] = clock.run(function()
                                clock.sleep(props.t)
                                blink[i] = 0
                                crops.dirty.grid = true
                            end)
                            
                            props.input(i, z)
                        end
                    end
                elseif crops.mode == 'redraw' then 
                    local g = crops.handler 

                    for i = 1,2 do
                        local x = i==2 and props.x_next or props.x_prev
                        local y = i==2 and props.y_next or props.y_prev

                        local lvl = props.levels[blink[i] + 1]

                        if lvl>0 then g:led(x, y, lvl) end
                    end
                end
            end
        end
    end
end

-- pattern_recorder. one-key controller for a pattern_time_extended instance
do
    local default_args = {
        blink_time = 0.25,
    }
    default_args.__index = default_args

    local default_props = {
        x = 1,                           --x position of the component
        y = 1,                           --y position of the component
        pattern = pattern_time.new(),    --pattern_time instance
        varibright = true,
    }
    default_props.__index = default_props

    function Produce.grid.pattern_recorder(args)
        args = args or {}
        setmetatable(args, default_args)

        local downtime = 0
        local lasttime = 0

        local blinking = false
        local blink = 0

        clock.run(function()
            while true do
                if blinking then
                    blink = 1
                    crops.dirty.grid = true
                    clock.sleep(args.blink_time)

                    blink = 0
                    crops.dirty.grid = true
                    clock.sleep(args.blink_time)
                else
                    blink = 0
                    clock.sleep(args.blink_time)
                end
            end
        end)

        return function(props)
            if crops.device == 'grid' then
                setmetatable(props, default_props)

                local pattern = props.pattern

                if crops.mode == 'input' then
                    local x, y, z = table.unpack(crops.args)

                    if x == props.x and y == props.y then
                        if z==1 then
                            downtime = util.time()
                        else
                            local theld = util.time() - downtime
                            local tlast = util.time() - lasttime
                            
                            if theld > 0.5 then --hold to clear
                                pattern:stop()
                                pattern:clear()
                                blinking = false
                            else
                                if pattern.data.count > 0 then
                                    if tlast < 0.3 then --double-tap to overdub
                                        pattern:resume()
                                        pattern:set_overdub(1)
                                        blinking = true
                                    else
                                        if pattern.rec == 1 then --play pattern / stop inital recording
                                            pattern:rec_stop()
                                            pattern:start()
                                            blinking = false
                                        elseif pattern.overdub == 1 then --stop overdub
                                            pattern:set_overdub(0)
                                            blinking = false
                                        else
                                            if pattern.play == 0 then --resume pattern
                                                pattern:resume()
                                                blinking = false
                                            elseif pattern.play == 1 then --pause pattern
                                                pattern:stop() 
                                                blinking = false
                                            end
                                        end
                                    end
                                else
                                    if pattern.rec == 0 then --begin initial recording
                                        pattern:rec_start()
                                        blinking = true
                                    else
                                        pattern:rec_stop()
                                        blinking = false
                                    end
                                end
                            end

                            crops.dirty.grid = true
                            lasttime = util.time()
                        end
                    end
                elseif crops.mode == 'redraw' then
                    local g = crops.handler

                    local lvl
                    do
                        local off = 0
                        local dim = (props.varibright == false) and 0 or 4
                        local med = (props.varibright == false) and 15 or 4
                        -- local medhi = (props.varibright == false) and 15 or 8 
                        local hi = 15

                        local empty = 0
                        -- local armed = ({ off, med })[blink + 1]
                        local armed = med
                        local recording = ({ off, med })[blink + 1]
                        local playing = hi
                        local paused = dim
                        local overdubbing = ({ dim, hi })[blink + 1]

                        lvl = (
                            pattern.rec==1 and (pattern.data.count>0 and recording or armed)
                            or (
                                pattern.data.count>0 and (
                                    pattern.overdub==1 and overdubbing
                                    or pattern.play==1 and playing
                                    or paused
                                ) or empty
                            )
                        )
                    end

                    if lvl>0 then g:led(props.x, props.y, lvl) end
                end
            end
        end
    end
end

--keymap_poly. grid-keyboard component based on Grid.momentaires, built for use with pattern_time_extended. uses pattern hooks to handle some edge cases that lead to hung notes or other wierdness. polyphonic version.
do
    local default_args = {
        action_on = function(idx) end,   --callback on key pressed, recieves key index (1 - size)
        action_off = function(idx) end,  --callback on key released, recieves key index (1 - size)
        size = 128,                      --number of keys in component (same as momentaires.size)
        pattern = nil,                   --instance of pattern_time_extended or mute_group. process 
                                         --    and hooks will be overwritten
    }
    default_args.__index = default_args

    local default_props = {
        x = 1,                           --x position of the component
        y = 1,                           --y position of the component
        levels = { 0, 15 },              --brightness levels. expects a table of 2 ints 0-15
        input = function(n, z) end,      --input callback, passes last key state on any input
        wrap = 16,                       --wrap to the next row/column every n keys
        flow = 'right',                  --primary direction to flow: 'up', 'down', 'left', 'right'
        flow_wrap = 'down',              --direction to flow when wrapping. must be perpendicular to flow
        padding = 0,                     --add blank spaces before the first key
                                         --note the lack of state prop – this is handled internally
    }
    default_props.__index = default_props

    function Produce.grid.keymap_poly(args)
        args = args or {}
        setmetatable(args, default_args)

        local state = {{}}

        local set_keys = function(value)
            local news, olds = value, state[1]
            
            for i = 1, args.size do
                local new = news[i] or 0
                local old = olds[i] or 0

                if new==1 and old==0 then args.action_on(i)
                elseif new==0 and old==1 then args.action_off(i) end
            end

            state[1] = value
            crops.dirty.grid = true
            crops.dirty.screen = true
        end

        -- local set_keys_wr = multipattern.wrap(args.multipattern, args.id, set_keys)

        args.pattern.process = set_keys
        local set_keys_wr = function(value)
            set_keys(value)
            args.pattern:watch(value)
        end

        state[2] = set_keys_wr

        local clear = function() set_keys({}) end
        local snapshot = function()
            local has_keys = false
            for i = 1, args.size do if (state[1][i] or 0) > 0 then  
                has_keys = true; break
            end end

            if has_keys then set_keys_wr(state[1]) end
        end

        local handlers = {
            pre_clear = clear,
            pre_rec_stop = snapshot,
            post_rec_start = snapshot,
            post_stop = clear,
        }

        args.pattern:set_all_hooks(handlers)
    
        local _momentaries = Grid.momentaries()

        return function(props)
            setmetatable(props, default_props)

            props.size = args.size
            props.state = state

            _momentaries(props)
        end
    end
end

--keymap_mono. grid-keyboard component based on Grid.momentaires, built for use with pattern_time_extended. uses pattern hooks to handle some edge cases that lead to hung notes or other wierdness. monophonic version.
do
    local default_args = {
        action = function(idx, gate) end,--callback key press/release, recieves key index (1 - size)
                                         --    and gate (0 or 1)
        size = 128,                      --number of keys in component (same as momentaires.size)
        pattern = nil,                   --instance of pattern_time_extended or mute_group. process 
                                         --    and hooks will be overwritten
    }
    default_args.__index = default_args

    local default_props = {
        x = 1,                           --x position of the component
        y = 1,                           --y position of the component
        levels = { 0, 15 },              --brightness levels. expects a table of 2 ints 0-15
        input = function(n, z) end,      --input callback, passes last key state on any input
        wrap = 16,                       --wrap to the next row/column every n keys
        flow = 'right',                  --primary direction to flow: 'up', 'down', 'left', 'right'
        flow_wrap = 'down',              --direction to flow when wrapping. must be perpendicular to flow
        padding = 0,                     --add blank spaces before the first key
                                         --note the lack of state prop – this is handled internally
    }
    default_props.__index = default_props

    function Produce.grid.keymap_mono(args)
        args = args or {}
        setmetatable(args, default_args)

        local state_momentaries = {{}}
        local state_integer = {1} 
        local state_gate = {0}

        local function set_idx_gate(idx, gate)
            state_integer[1] = idx
            state_gate[1] = gate
            args.action(idx, gate)

            crops.dirty.grid = true
            crops.dirty.screen = true
        end
        
        -- local set_idx_gate_wr = multipattern.wrap(args.multipattern, args.id, set_idx_gate)

        args.pattern.process = function(e) set_idx_gate(table.unpack(e)) end
        local set_idx_gate_wr = function(idx, gate)
            set_idx_gate(idx, gate)
            args.pattern:watch({ idx, gate })
        end

        local set_states = function(value)
            local gate = 0
            local idx = state_integer[1]

            for i = args.size, 1, -1 do
                local v = value[i] or 0

                if v > 0 then
                    gate = 1
                    idx = i
                    break;
                end
            end

            state_momentaries[1] = value
            set_idx_gate_wr(idx, gate)
        end

        state_momentaries[2] = set_states

        local clear = function() set_idx_gate(state_integer[1], 0) end
        local snapshot = function()
            if state_gate[1] > 0 then set_idx_gate_wr(state_integer[1], state_gate[1]) end
        end

        local handlers = {
            pre_clear = clear,
            pre_rec_stop = snapshot,
            post_rec_start = snapshot,
            post_stop = clear,
        }

        args.pattern:set_all_hooks(handlers)
    
        local _momentaries = Grid.momentaries()
        local _integer = Grid.integer()

        return function(props)
            -- setmetatable(props, default_props)

            props.size = args.size

            local momentaries_props = {}
            local integer_props = {}
            for k,v in pairs(props) do 
                momentaries_props[k] = props[k] 
                integer_props[k] = props[k] 
            end

            momentaries_props.state = state_momentaries
            integer_props.state = state_integer
        
            if crops.mode == 'input' then
                _momentaries(momentaries_props)
            elseif crops.mode == 'redraw' then
                if state_gate[1] > 0 then
                    _integer(integer_props)
                end
            end
        end
    end
end

--keymap_sequeggiator
do
    local default_props = {
        x = 1,                           --x position of the component
        y = 1,                           --y position of the component
        size = 128,                      --number of keys in component
        state = {{}},                    --state is a sequece of indices
        step = 1,                        --the current step in the sequence, this key is lit
        levels = { 0, 15 },              --brightness levels. expects a table of 2 ints 0-15
        input = function(n, z) end,      --input callback, passes last key state on any input
        wrap = 16,                       --wrap to the next row/column every n keys
        flow = 'right',                  --primary direction to flow: 'up', 'down', 'left', 'right'
        flow_wrap = 'down',              --direction to flow when wrapping. must be perpendicular to flow
        padding = 0,                     --add blank spaces before the first key
                                         --note the lack of state prop – this is handled internally
    }
    default_props.__index = default_props

    function Produce.grid.keymap_sequeggiator()
        local NEW_SEQ, PLAYBACK = 1,2

        local mode = NEW_SEQ

        return function(props)
            setmetatable(props, default_props)

            local function new_seq_press(idx)
            end

            local function new_seq_release(idx)
            end

            local function playback_tap(idx)
            end

            local function playback_double_tap(idx)
            end

            local function playback_hold(idx)
            end

            if crops.mode == 'input' then
            elseif crops.mode == 'redraw' then
            end
        end
    end
end

return Produce.grid
