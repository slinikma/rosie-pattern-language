---- -*- Mode: Lua; -*- 
----
---- test-api.lua
----
---- (c) 2016, Jamie A. Jennings
----

json = require "cjson"
package.loaded.api = false			    -- force re-load of api.lua

if not color_write then
   color_write = function(channel, ignore_color, ...)
		    for _,v in ipairs({...}) do
		       channel:write(v)
		    end
		 end
end

function red_write(...)
   local str = ""
   for _,v in ipairs({...}) do str = str .. tostring(v); end
   color_write(io.stdout, "red", str)
end

local count = 0
local fail_count = 0
local heading_count = 0
local subheading_count = 0
local messages = {}
local current_heading = "Heading not assigned"
local current_subheading = "Subheading not assigned"

function check(thing, message)
   count = count + 1
   heading_count = heading_count + 1
   subheading_count = subheading_count + 1
   if not (thing) then
      red_write("X")
      table.insert(messages, {h=current_heading or "Heading unassigned",
			      sh=current_subheading or "",
			      shc=subheading_count,
			      hc=heading_count,
			      c=count,
			      m=message or ""})
      fail_count = fail_count + 1
   end
   io.stdout:write(".")
end

function heading(label)
   heading_count = 0
   subheading_count = 0
   current_heading = label
   current_subheading = ""
   io.stdout:write("\n", label, " ")
end

function subheading(label)
   subheading_count = 0
   current_subheading = label
   io.stdout:write("\n\t", label, " ")
end

function ending()
   io.stdout:write("\n\n** TOTAL ", tostring(count), " tests attempted.\n")
   if fail_count == 0 then
      io.stdout:write("** All tests passed.\n")
   else
      io.stdout:write("** ", tostring(fail_count), " tests failed:\n")
      for _,v in ipairs(messages) do
	 red_write(v.h, ": ", v.sh, ": ", "#", v.shc, " ", v.m, "\n")
      end
   end
end

arg_err_engine_id = "Argument error: engine id not a string"

----------------------------------------------------------------------------------------
heading("Require api")
----------------------------------------------------------------------------------------
api = require "api"

check(type(api)=="table")
check(api.VERSION)
check(type(api.VERSION=="string"))

----------------------------------------------------------------------------------------
heading("Engine")
----------------------------------------------------------------------------------------
subheading("new_engine")
check(type(api.new_engine)=="function")
ok, eid = api.new_engine("hello")
check(ok)
check(type(eid)=="string")
ok, eid2 = api.new_engine("hello")
check(ok)
check(type(eid2)=="string")
check(eid~=eid2, "engine ids (as generated by Lua) must be unique")

subheading("ping_engine")
check(type(api.ping_engine)=="function")
ok, name = api.ping_engine(eid)
check(ok)
check(name=="hello")
ok, msg = api.ping_engine()
check(not ok)
check(msg==arg_err_engine_id)
ok, msg = api.ping_engine("foobar")
check(not ok)
check(msg=="Argument error: invalid engine id")

subheading("delete_engine")
check(type(api.delete_engine)=="function")
ok, msg = api.delete_engine(eid2)
check(ok)
check(msg=="")
ok, msg = api.delete_engine(eid2)
check(ok, "idempotent delete function")
check(msg=="")

ok, msg = api.ping_engine(eid2)
check(not ok)
check(msg=="Argument error: invalid engine id")
check(api.ping_engine(eid), "other engine with same name still exists")

subheading("get_env")
check(type(api.get_env)=="function")
ok, env = api.get_env(eid)
check(ok)
check(type(env)=="string", "environment is returned as a JSON string")
j = json.decode(env)
check(type(j)=="table")
check(j["."].type=="alias", "env contains built-in alias '.'")
check(j["$"].type=="alias", "env contains built-in alias '$'")
ok, msg = api.get_env()
check(not ok)
check(msg==arg_err_engine_id)
ok, msg = api.get_env("hello")
check(not ok)
check(msg=="Argument error: invalid engine id")

subheading("get_definition")
check(type(api.get_definition)=="function")
ok, msg = api.get_definition()
check(not ok)
check(msg==arg_err_engine_id)
ok, msg = api.get_definition("hello")
check(not ok)
check(msg=="Argument error: invalid engine id")
ok, def = api.get_definition(eid, "$")
check(ok, "can get a definition for '$'")
check(def=="alias $ = // built-in RPL pattern //")

----------------------------------------------------------------------------------------
heading("Load")
----------------------------------------------------------------------------------------
subheading("load_string")
check(type(api.load_string)=="function")
ok, msg = api.load_string()
check(not ok)
check(msg==arg_err_engine_id)
ok, msg = api.load_string("hello")
check(not ok)
check(msg=="Argument error: invalid engine id")
ok, msg = api.load_string(eid, "foo")
check(not ok)
check(1==msg:find("Compile error: reference to undefined identifier foo"))
ok, msg = api.load_string(eid, 'foo = "a"')
check(ok)
check(msg=="")
ok, env = api.get_env(eid)
check(ok)
j = json.decode(env)
check(j["foo"].type=="definition", "env contains newly defined identifier")
ok, msg = api.load_string(eid, 'bar = foo / "1" $')
check(ok)
check(msg=="")
ok, env = api.get_env(eid)
check(ok)
j = json.decode(env)
check(j["bar"].type=="definition", "env contains newly defined identifier")
ok, def = api.get_definition(eid, "bar")
check(def=='bar = foo / "1" $')
ok, msg = api.load_string(eid, 'x = //', "syntax error")
check(not ok)
check(2==msg:find("(Note: Syntax error reporting is currently rather coarse.)"))
check(60==msg:find("Syntax error at line 1: x = //"))
ok, env = api.get_env(eid)
check(ok)
j = json.decode(env)
check(not j["x"])

ok, msg = api.load_string(eid, '-- comments and \n -- whitespace\t\n\n',
   "an empty list of ast's is the result of parsing comments and whitespace")
check(ok)
check(msg=="")

g = [[grammar
  S = {"a" B} / {"b" A} / "" 
  A = {"a" S} / {"b" A A}
  B = {"b" S} / {"a" B B}
end]]

ok, msg = api.load_string(eid, g)
check(ok)
check(msg=="")

ok, def = api.get_definition(eid, "S")
check(ok)
check(1==def:find("S = grammar"))

ok, env = api.get_env(eid)
check(ok)
check(type(env)=="string", "environment is returned as a JSON string")
j = json.decode(env)
check(j["S"].type=="definition")


subheading("load_file")
check(type(api.load_file)=="function")
ok, msg = api.load_file()
check(not ok)
check(msg==arg_err_engine_id)
ok, msg = api.load_file("hello")
check(not ok)
check(msg=="Argument error: invalid engine id")

ok, msg = api.load_file(eid, "test/ok.rpl")
check(ok)
check(msg=="")
ok, env = api.get_env(eid)
check(ok)
j = json.decode(env)
check(j["num"].type=="definition")
check(j["S"].type=="alias")
ok, def = api.get_definition(eid, "W")
check(ok)
check(def=="alias W = !w any")
ok, msg = api.load_file(eid, "test/undef.rpl")
check(not ok)
check(1==msg:find("Compile error: reference to undefined identifier spaces\nAt line 9:"))
ok, env = api.get_env(eid)
check(ok)
j = json.decode(env)
check(not j["badword"], "an identifier that didn't compile should not end up in the environment")
check(j["undef"], "definitions in a file prior to an error will end up in the environment... (sigh)")
check(not j["undef2"], "definitions in a file after to an error will NOT end up in the environment")
ok, msg = api.load_file(eid, "test/synerr.rpl")
check(not ok)
check(2==msg:find("(Note: Syntax error reporting is currently rather coarse.)"))
check(msg:find('Syntax error at line 8: // "abc"'))
check(msg:find('foo = "foobar" // "abc"'))

ok, msg = api.load_file(eid, "./thisfile/doesnotexist")
check(not ok)
check(msg:find("cannot open file"))
check(msg:find("./thisfile/doesnotexist"))

ok, msg = api.load_file(eid, "/etc")
check(not ok)
check(msg:find("unreadable file"))
check(msg:find("/etc"))

subheading("load_manifest")
check(type(api.load_manifest)=="function")
ok, msg = api.get_definition()
check(not ok)
check(msg==arg_err_engine_id)
ok, msg = api.get_definition("hello")
check(not ok)
check(msg=="Argument error: invalid engine id")
ok, msg = api.load_manifest(eid, "test/manifest")
check(ok)
check(msg=="")
ok, env = api.get_env(eid)
check(ok)
j = json.decode(env)
check(j["manifest_ok"].type=="definition")

ok, msg = api.load_manifest(eid, "test/manifest.err")
check(not ok)
check(1==msg:find("Compiler: cannot open file"))

ok, msg = api.load_manifest(eid, "test/manifest.synerr") -- contains a //
check(not ok)
check(1==msg:find("Compiler: unreadable file"))


----------------------------------------------------------------------------------------
heading("Match")
----------------------------------------------------------------------------------------
subheading("match_using_exp")
check(type(api.match_using_exp)=="function")
ok, msg = api.match_using_exp()
check(not ok)
check(msg==arg_err_engine_id)

ok, msg = api.match_using_exp(eid)
check(not ok)
check(msg:find("missing pattern"))

ok, match, left = api.match_using_exp(eid, ".", "A")
check(ok)
check(left==0)
j = json.decode(match)
check(j["*"].text=="A")
check(j["*"].pos==1)

ok, match, left = api.match_using_exp(eid, '{"A".}', "ABC")
check(ok)
check(left==1)
j = json.decode(match)
check(j["*"].text=="AB")
check(j["*"].pos==1)

ok, msg = api.load_manifest(eid, "MANIFEST")
check(ok)

ok, match, left = api.match_using_exp(eid, 'common.number', "1FACE x y")
check(ok)
check(left==3)
j = json.decode(match)
check(j["common.number"].text=="1FACE")
check(j["common.number"].pos==1)

ok, match, left = api.match_using_exp(eid, '[:space:]* common.number', "   1FACE")
check(ok)
check(left==0)
j = json.decode(match)
check(j["*"].pos==1)
check(j["*"].subs[1]["common.number"])
check(j["*"].subs[1]["common.number"].pos==4)


subheading("match_set_exp")
check(type(api.match_set_exp)=="function")
ok, msg = api.match_set_exp()
check(not ok)
check(msg==arg_err_engine_id)

ok, msg = api.match_set_exp(eid)
check(not ok)
check(msg:find("missing pattern"))

ok, msg = api.match_set_exp(eid, "common.dotted_identifier")
check(ok)
check(msg=="")


subheading("match")
check(type(api.match)=="function")
ok, msg = api.match()
check(not ok)
check(msg==arg_err_engine_id)

ok, msg = api.match(eid)
check(not ok)
check(msg:find("without any input"))		    -- throws an engine error.  fix!

ok, match, left = api.match(eid, "x.y.z")
check(ok)
check(left==0)
j = json.decode(match)
check(j["common.dotted_identifier"].text=="x.y.z")
check(j["common.dotted_identifier"].subs[2]["common.identifier_plus_plus"].text=="y")

ok, match, left = api.match_using_exp(eid, 'common.number', "1FACE x y")
check(ok, "checking that match_using_exp still works after a call to match_set_exp")
check(left==3)

ok, match, left = api.match(eid, "x.y.z")
check(ok, "verifying that the engine exp has NOT been reset by match_set_exp")
check(left==0)



ending()




       

