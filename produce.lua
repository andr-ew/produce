local Produce = {
    grid = {},
    enc = {},
    key = {},
    screen = {},
    arc = {}
}

-- grid.pattern recorder. one-key controller for a pattern_time instance
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
        events = {
            pre_clear = function() end,
            post_stop = function() end,
            pre_resume = function() end,
            pre_rec_stop = function() end,
            post_rec_start = function() end,
        }
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
                if rawget(props, 'events') then
                    setmetatable(props.events, default_props.events)
                end

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
                                props.events.pre_clear()
                                pattern:clear()
                                blinking = false
                            else
                                if pattern.data.count > 0 then
                                    if tlast < 0.3 then --double-tap to overdub
                                        pattern:resume()
                                        pattern:set_overdub(1)
                                        props.events.post_rec_start()
                                        blinking = true
                                    else
                                        if pattern.rec == 1 then --play pattern / stop inital recording
                                            props.events.pre_rec_stop()
                                            pattern:rec_stop()
                                            pattern:start()
                                            blinking = false
                                        elseif pattern.overdub == 1 then --stop overdub
                                            props.events.pre_rec_stop()
                                            pattern:set_overdub(0)
                                            blinking = false
                                        else
                                            if pattern.play == 0 then --resume pattern
                                                props.events.pre_resume()
                                                pattern:resume()
                                                blinking = false
                                            elseif pattern.play == 1 then --pause pattern
                                                pattern:stop() 
                                                props.events.post_stop()
                                                blinking = false
                                            end
                                        end
                                    end
                                else
                                    if pattern.rec == 0 then --begin initial recording
                                        pattern:rec_start()
                                        props.events.post_rec_start()
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


-- screen.text_highlight. screen.text, but boxed-out
do
    local defaults = {
        text = 'abc',            --string to display
        x = 10,                  --x position
        y = 10,                  --y position
        font_face = 1,           --font face
        font_size = 8,           --font size
        levels = { 4, 15 },      --table of 2 brightness levels, 0-15 (text, highlight box)
        flow = 'right',          --direction for text to flow: 'left', 'right', or 'center'
        font_headroom = 3/8,     --used to calculate height of letters. might need to adjust for non-default fonts
        padding = 1,             --padding around highlight box
        fixed_width = nil,
    }
    defaults.__index = defaults

    function Produce.screen.text_highlight()
        return function(props)
            if crops.device == 'screen' then
                setmetatable(props, defaults)

                if crops.mode == 'redraw' then
                    screen.font_face(props.font_face)
                    screen.font_size(props.font_size)

                    local x, y, flow, v = props.x, props.y, props.flow, props.text
                    local w = props.fixed_width or screen.text_extents(v)
                    local h = props.font_size * (1 - props.font_headroom)

                    if props.levels[2] > 0 then
                        screen.level(props.levels[2])
                        screen.rect(
                            x - props.padding + (props.squish and 1 or 0), 
                            --TODO: the nudge is wierd... fix if including in common lib
                            y - h - props.padding + (props.nudge and 0 or 1),
                            w + props.padding*2 - (props.squish and 1 or 0),
                            h + props.padding*2
                        )
                        screen.fill()
                    end
                
                    screen.move(x, y)
                    screen.level(props.levels[1])

                    if flow == 'left' then screen.text_right(v)
                    else screen.text(v) end
                end
            end
        end
    end
end

-- screen.list_highlight. screen.list, but focused item is boxed-out
do
    local defaults = {
        text = {},               --list of strings to display. non-numeric keys are displayed as labels with thier values. (e.g. { cutoff = value })
        x = 10,                  --x position
        y = 10,                  --y position
        font_face = 1,           --font face
        font_size = 8,           --font size
        margin = 5,              --pixel space betweeen list items
        levels = { 4, 15 },      --table of 2 brightness levels, 0-15 (text, highlight box)
        focus = 2,               --only this index in the resulting list will be highlighted,
        flow = 'right',          --direction of list to flow: 'up', 'down', 'left', 'right'
        font_headroom = 3/8,     --used to calculate height of letters. might need to adjust for non-default fonts
        padding = 1,             --padding around highlight box
        -- font_leftroom = 1/16,
        fixed_width = nil,
    }
    defaults.__index = defaults

    function Produce.screen.list_highlight()
        return function (props)
            if crops.device == 'screen' then
                setmetatable(props, defaults)

                if crops.mode == 'redraw' then
                    screen.font_face(props.font_face)
                    screen.font_size(props.font_size)

                    local x, y, i, flow = props.x, props.y, 1, props.flow

                    local function txt(v)
                        local focus = i == props.focus
                        local w = props.fixed_width or screen.text_extents(v)
                        local h = props.font_size * (1 - props.font_headroom)

                        if focus then
                            screen.level(props.levels[2])
                            screen.rect(
                                x - props.padding, 
                                --TODO: the nudge is wierd... fix if including in common lib
                                y - h - props.padding + (props.nudge and 0 or 1),
                                w + props.padding*2,
                                h + props.padding*2
                            )
                            screen.fill()
                        end
                        
                        screen.move(x, y)
                        screen.level(focus and 0 or props.levels[1])

                        if flow == 'left' then screen.text_right(v)
                        else screen.text(v) end

                        if flow == 'right' then 
                            x = x + w + props.margin
                        elseif flow == 'left' then 
                            x = x - w - props.margin
                        elseif flow == 'down' then 
                            y = y + h + props.margin
                        elseif flow == 'up' then 
                            y = y - h - props.margin
                        end

                        i = i + 1
                    end

                    if #props.text > 0 then for _,v in ipairs(props.text) do txt(v) end
                    else for k,v in pairs(props.text) do txt(k); txt(v) end end
                end
            end
        end
    end
end

-- screen.list_underline. screen.list, but focused item is underlined
do
    local defaults = {
        text = {},               --list of strings to display. non-numeric keys are displayed as labels with thier values. (e.g. { cutoff = value })
        x = 10,                  --x position
        y = 10,                  --y position
        font_face = 1,           --font face
        font_size = 8,           --font size
        margin = 5,              --pixel space betweeen list items
        levels = { 4, 15 },      --table of 2 brightness levels, 0-15 (text, underline)
        focus = 2,               --only this index in the resulting list will be underlined
        flow = 'right',          --direction of list to flow: 'up', 'down', 'left', 'right'
        font_headroom = 3/8,     --used to calculate height of letters. might need to adjust for non-default fonts
        padding = 1,             --padding below text
        -- font_leftroom = 1/16,
        fixed_width = nil,
    }
    defaults.__index = defaults

    function Produce.screen.list_underline()
        return function(props)
            if crops.device == 'screen' then
                setmetatable(props, defaults)

                if crops.mode == 'redraw' then
                    screen.font_face(props.font_face)
                    screen.font_size(props.font_size)

                    local x, y, i, flow = props.x, props.y, 1, props.flow

                    local function txt(v)
                        local focus = i == props.focus
                        local w = props.fixed_width or screen.text_extents(v)
                        local h = props.font_size * (1 - props.font_headroom)

                        if focus then
                            screen.level(props.levels[2])
                            screen.move(flow == 'left' and x-w or x, y + props.padding + 1)
                            screen.line_width(1)
                            screen.line_rel(w, 0)
                            screen.stroke()
                        end
                        
                        screen.move(x, y)
                        screen.level(props.levels[(i == props.focus) and 2 or 1])

                        if flow == 'left' then screen.text_right(v)
                        else screen.text(v) end

                        if flow == 'right' then 
                            x = x + w + props.margin
                        elseif flow == 'left' then 
                            x = x - w - props.margin
                        elseif flow == 'down' then 
                            y = y + h + props.margin
                        elseif flow == 'up' then 
                            y = y - h - props.margin
                        end

                        i = i + 1
                    end

                    if #props.text > 0 then for _,v in ipairs(props.text) do txt(v) end
                    else for k,v in pairs(props.text) do txt(k); txt(v) end end
                end
            end
        end
    end
end

return Produce
