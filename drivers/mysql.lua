local mysql = require'resty.mysql'
local quote_sql_str = ngx.quote_sql_str
local assert = assert
local ipairs = ipairs
local table_concat = table.concat
local table_insert = table.insert
local lpeg = require'lpeg'
local ngx = ngx

local open = function(conf)
    local connect = function()
        local db, err = mysql:new()
        assert(not err, "failed to create: ", err)

        local ok, err, errno, sqlstate = db:connect(conf)
        assert(ok, "failed to connect: ", err, ": ", errno, " ", sqlstate)

        if conf.charset then
            if db:get_reused_times() == 0 then
                db:query("SET NAMES " .. conf.charset)
            end
        end

        return db
    end

    local config = function()
        return conf
    end

    local query = function(query_str)
        if conf.debug then
            ngx.log(ngx.DEBUG, '[SQL] ' .. query_str)
        end

        local db = connect()
        local res, err, errno, sqlstate = db:query(query_str)
        if not res then
            return false, table_concat({"bad result: " .. err, errno, sqlstate}, ', ') 
        end

        if err == 'again' then res = { res } end
        while err == "again" do
            local tmp
            tmp, err, errno, sqlstate = db:read_result()
            if not tmp then
                return false, table_concat({"bad result: " .. err, errno, sqlstate}, ', ') 
            end

            table_insert(res, tmp)
        end

        local ok, err = db:set_keepalive(10000, 50)
        if not ok then
            ngx.log(ngx.ERR, "failed to set keepalive: ", err)
        end

        return true, res
    end

    local escape_identity = function(id)
        local qchar = '`'
        local openp, endp = lpeg.P'[', lpeg.P']'
        local quote_pat = openp * lpeg.C(( 1 - endp)^1) * endp
        local repl = qchar .. '%1' .. qchar
        return lpeg.Cs((quote_pat/repl + 1)^0):match(id)
    end

    local get_schema = function(table_name)
        -- {Null="YES",Field="user_position",Type="varchar(45)",Extra="",Key="",Default=""}
        local ok, res = query('desc ' .. escape_identity(table_name))
        assert(ok, res)

        local fields = {  }
        for _, f in ipairs(res) do
            fields[f.Field] = f
            if f.Key == 'PRI' then
                if fields.__pk__ then
                    error('not implement for tables have multiple pk')
                end
                fields.__pk__ = f.Field
            end
        end

        return fields
    end

    return { 
        query = query;
        get_schema = get_schema;
        config = config;
        escape_identity = escape_identity;
    }
end


return open
