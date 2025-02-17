local GUI = require("GUI")
local modemPort = 1000
local syncPort = 199
local dbPort = 180

local adminCard = "admincard"

local component = require("component")
local ser = require("serialization")
local JSON = require("JSON")
local compat = require("Compat") --compatability layer so it all works between OpenOS and MineOS

local aRD = compat.fs.path(compat.system.getCurrentScript())
local stylePath = aRD.."Styles/"
local style = "default.lua"
local modulesPath = aRD .. "Modules/"
local loc = compat.loc compat.system.getLocalization(aRD .. "Localizations/")

--------

local workspace, window, menu, userTable, settingTable, modulesLayout, modules, permissions
local addVarArray, updateButton, moduleLabel
local usernamename, userpasspass

local dataBuffer = {}--Progress saving of modules
local configBuffer = {} --All module's config options in database

----------

local prgName = loc.name
local version = "v4.0.2"

local online = true
local extraOff = false

local modem

local tableRay = {}
local prevmod

local download = "https://cadespc.com/servertine/modules/"
local debug = false

modID = 0
isDevMode = false
--local moduleDownloadDebug = false

if component.isAvailable("modem") then
  modem = component.modem
else
  GUI.alert(loc.modemalert)
  return
end
if component.isAvailable("internet") then

else
  GUI.alert("No internet card inserted")
  return
end


-----------

local function convert( chars, dist, inv )
  return string.char( ( string.byte( chars ) - 32 + ( inv and -dist or dist ) ) % 95 + 32 )
end

local function crypt(str,k,inv)
  local enc= "";
  for i=1,#str do
    if(#str-k[5] >= i or not inv)then
      for inc=0,3 do
        if(i%4 == inc)then
          enc = enc .. convert(string.sub(str,i,i),k[inc+1],inv);
          break;
        end
      end
    end
  end
  if(not inv)then
    for i=1,k[5] do
      enc = enc .. string.char(math.random(32,126));
    end
  end
  return enc;
end

local function split(s, delimiter)
  local result = {};
  for match in (s..delimiter):gmatch("(.-)"..delimiter) do
    table.insert(result, match);
  end
  return result;
end

--// exportstring( string )
--// returns a "Lua" portable version of the string
local function exportstring( s )
  s = string.format( "%q",s )
  -- to replace
  s = string.gsub( s,"\\\n","\\n" )
  s = string.gsub( s,"\r","\\r" )
  s = string.gsub( s,string.char(26),"\"..string.char(26)..\"" )
  return s
end

local function callModem(callPort,...) --Does it work?
  modem.broadcast(callPort,...)
  local e, _, from, port, _, msg,a,b,c,d,f,g,h
  repeat
    e, a,b,c,d,f,g,h = compat.event.pull(1)
  until(e == "modem_message" or e == nil)
  if e == "modem_message" then
    return true,a,b,c,d,f,g,h
  else
    return false
  end
end

local function checkPerms(base,data, reverse)
  for i=1,#data,1 do
    if permissions["~" .. base .."." .. data[i]] == true then
      return reverse == true and true or false
    end
  end
  if permissions["~" .. base .. ".*"] == true then
    return reverse == true and true or false
  end
  if permissions["all"] == true or permissions[base .. ".*"] == true then
    return reverse == false and true or false
  end
  for i=1,#data,1 do
    if permissions[base .. "." .. data[i]] == true then
      return reverse == false and true or false
    end
  end
  return reverse == true and true or false
end

----------Callbacks

local function updateServer(table)
  local data = {}
  if table then
    for _,value in pairs(table) do
      data[value] = userTable[value]
    end
  else
    data = userTable
  end
  data = ser.serialize(data)
  local crypted = crypt(data, settingTable.cryptKey)
  if modem.isOpen(modemPort) == false then
    modem.open(modemPort)
  end
  modem.broadcast(modemPort, "updateuserlist", crypted)
end

local function devMod(...)
  local module = {}
  local component = require("component")

  local workspace, window, loc, database, style, permissions = table.unpack({...})

  module.init = function()

  end

  module.onTouch = function() --TODO: Prepare this for Module installation, user permissions, and more.
    local userEditButton, moduleInstallButton, settingButton, layout

    local function disabledSet()
      userEditButton.disabled = online == false and true or checkPerms("dev",{"usermanagement"},true)
      moduleInstallButton.disabled = online == false and true or checkPerms("dev",{"systemmanagement"},true)
      if online then
        settingButton.disabled = checkPerms("dev",{"systemmanagement"},true)
      else
        settingButton.disabled = false
      end
    end

    --Big Callbacks
    local function beginUserEditing() --136 width, 33 height big area, 116 width, 33 height extra area.
      local userList, permissionList, permissionInput, addPerm, deletePerm, users, addUser, deleteUser, userInput, passwordInput
      local listUp, listDown, listNum, listUp2, listDown2, listNum2

      local pageMult = 10
      local listPageNumber = 0
      local previousPage = 0

      local listPageNumber2 = 0
      local previousPage2 = 0

      local function updateUserStuff()
        local selectedId = pageMult * listPageNumber + userList.selectedItem
        local disselect = pageMult * listPageNumber2
        local pees = userList:getItem(userList.selectedItem)
        permissionList:removeChildren()
        for i=disselect+1,disselect+pageMult,1 do
          if users[pees.text].perms[i] == nil then

          else
            permissionList:addItem(users[pees.text].perms[i])
          end
        end
        permissionInput.disabled = false
        addPerm.disabled = false
        deletePerm.disabled = false
      end

      local function updateList()
        local selectedId = userList.selectedItem
        userList:removeChildren()
        local temp = pageMult * listPageNumber
        local count = 0
        for key,_ in pairs(users) do
          count = count + 1
          if count >= temp + 1 and count <= temp + pageMult then
            userList:addItem(key).onTouch = updateUserStuff
          end
        end
        if previousPage == listPageNumber then
          userList.selectedItem = selectedId
        else
          previousPage = listPageNumber
        end
      end

      local function pageCallback(workspace,button)
        local function canFresh()
          updateList()
          updateUserStuff()
        end
        local count = {}
        for key,_ in pairs(users) do
          table.insert(count,key)
        end
        if button.isPos then
          if button.isListNum == 1 then
            if listPageNumber < #count/pageMult - 1 then
              listPageNumber = listPageNumber + 1
              canFresh()
            end
          else
            if listPageNumber2 < #users[count[pageMult * listPageNumber + userList.selectedItem]].perms/pageMult - 1 then
              listPageNumber2 = listPageNumber2 + 1
              canFresh()
            end
          end
        else
          if button.isListNum == 1 then
            if listPageNumber > 0 then
              listPageNumber = listPageNumber - 1
              canFresh()
            end
          else
            if listPageNumber2 > 0 then
              listPageNumber2 = listPageNumber2 - 1
              canFresh()
            end
          end
        end
      end

      layout:removeChildren()
      userEditButton.disabled = true
      moduleInstallButton.disabled = true
      settingButton.disabled = true
      
      local e,_,_,_,_,peed,meed = callModem(modemPort,"signIn",crypt(ser.serialize({["command"]="grab",["user"]=usernamename,["pass"]=userpasspass}),settingTable.cryptKey))
      if e then
        if crypt(peed,settingTable.cryptKey,true) == "true" then
          users = ser.unserialize(crypt(meed,settingTable.cryptKey,true))
          layout:addChild(GUI.panel(1,1,37,33,style.listPanel))
          userList = layout:addChild(GUI.list(2, 2, 35, 31, 3, 0, style.listBackground, style.listText, style.listAltBack, style.listAltText, style.listSelectedBack, style.listSelectedText, false))
          userList:addItem("HELLO")
          listPageNumber = 0
          layout:addChild(GUI.panel(40,1,37,33,style.listPanel))
          permissionList = layout:addChild(GUI.list(41, 2, 35, 31, 3, 0, style.listBackground, style.listText, style.listAltBack, style.listAltText, style.listSelectedBack, style.listSelectedText, false))
          listPageNumber2 = 0
          updateList()
          --local permissionInput, addPerm, deletePerm, users, addUser, deleteUser
          userInput = layout:addChild(GUI.input(80,1,30,1, style.passInputBack,style.passInputText,style.passInputPlaceholder,style.passInputFocusBack,style.passInputFocusText, "", loc.inputname))
          passwordInput = layout:addChild(GUI.input(80,3,30,1, style.passInputBack,style.passInputText,style.passInputPlaceholder,style.passInputFocusBack,style.passInputFocusText, "", loc.input .. " " .. loc.pass,true,"*"))
          addUser = layout:addChild(GUI.button(80,5,16,1,style.bottomButton, style.bottomText, style.bottomSelectButton, style.bottomSelectText, loc.add .. " " .. loc.user))
          addUser.onTouch = function()
            users[userInput.text] = {["pass"]=crypt(passwordInput.text,settingTable.cryptKey),["perms"]={}}
            modem.broadcast(modemPort,"signIn",crypt(ser.serialize({["command"]="update",["data"]=users}),settingTable.cryptKey))
            userInput.text = ""
            passwordInput.text = ""
            updateList()
          end
          deleteUser = layout:addChild(GUI.button(100,5,16,1,style.bottomButton, style.bottomText, style.bottomSelectButton, style.bottomSelectText, loc.delete .. " " .. loc.user))
          deleteUser.onTouch = function()
            users[userList:getItem(userList.selectedItem).text] = nil
            modem.broadcast(modemPort,"signIn",crypt(ser.serialize({["command"]="update",["data"]=users}),settingTable.cryptKey))
            updateList()
          end
          layout:addChild(GUI.panel(80,7,36,1,style.bottomDivider))
          permissionInput = layout:addChild(GUI.input(80,9,30,1, style.passInputBack,style.passInputText,style.passInputPlaceholder,style.passInputFocusBack,style.passInputFocusText, "", loc.input .. " " .. loc.perm))
          addPerm = layout:addChild(GUI.button(80,11,16,1,style.bottomButton, style.bottomText, style.bottomSelectButton, style.bottomSelectText, loc.add .. " " .. loc.perm))
          addPerm.onTouch = function()
            table.insert(users[userList:getItem(userList.selectedItem).text].perms,permissionInput.text)
            permissionInput.text = ""
            modem.broadcast(modemPort,"signIn",crypt(ser.serialize({["command"]="update",["data"]=users}),settingTable.cryptKey))
            updateUserStuff()
          end
          addPerm.disabled = true
          deletePerm = layout:addChild(GUI.button(100,11,16,1,style.bottomButton, style.bottomText, style.bottomSelectButton, style.bottomSelectText, loc.delete .. " " .. loc.perm))
          deletePerm.onTouch = function()
            table.remove(users[userList:getItem(userList.selectedItem).text].perms,pageMult * listPageNumber2 + permissionList.selectedItem)
            modem.broadcast(modemPort,"signIn",crypt(ser.serialize({["command"]="update",["data"]=users}),settingTable.cryptKey))
            updateUserStuff()
          end
          addPerm.disabled = true

          listNum = layout:addChild(GUI.label(2,33,3,3,style.listPageLabel,tostring(listPageNumber + 1)))
          listUp = layout:addChild(GUI.button(8,33,3,1, style.listPageButton, style.listPageText, style.listPageSelectButton, style.listPageSelectText, "+"))
          listUp.onTouch, listUp.isPos, listUp.isListNum = pageCallback,true,1
          listDown = layout:addChild(GUI.button(12,33,3,1, style.listPageButton, style.listPageText, style.listPageSelectButton, style.listPageSelectText, "-"))
          listDown.onTouch, listDown.isPos, listDown.isListNum = pageCallback,false,1

          listNum2 = layout:addChild(GUI.label(41,33,3,3,style.listPageLabel,tostring(listPageNumber2 + 1)))
          listUp2 = layout:addChild(GUI.button(49,33,3,1, style.listPageButton, style.listPageText, style.listPageSelectButton, style.listPageSelectText, "+"))
          listUp2.onTouch, listUp2.isPos, listUp2.isListNum = pageCallback,true,2
          listDown2 = layout:addChild(GUI.button(53,33,3,1, style.listPageButton, style.listPageText, style.listPageSelectButton, style.listPageSelectText, "-"))
          listDown2.onTouch, listDown2.isPos, listDown2.isListNum = pageCallback,false,2
        else
          GUI.alert(loc.incorrectpermusergrab)
          disabledSet()
        end
      else
        GUI.alert(loc.userpermfail)
        disabledSet()
      end
    end

    local function moduleInstallation()
      layout:removeChildren()
      userEditButton.disabled = true
      moduleInstallButton.disabled = true
      settingButton.disabled = true

      local moduleTable
      local displayList, downloadList, bothArray, cancelButton, downloadButton,moveRight,moveLeft
      --local listUp, listDown, listNum, listUp2, listDown2, listNum2

      local pageMult = 9
      local listPageNumber = 0
      local previousPage = 0

      local listPageNumber2 = 0
      local previousPage2 = 0

      local function updateLists() --FIXME: Fix button getting stuck red (bug?), and random crash back at home
        local leftSelect = pageMult * listPageNumber + displayList.selectedItem
        local rightSelect = pageMult * listPageNumber2 + downloadList.selectedItem
        displayList:removeChildren()
        downloadList:removeChildren()
        local text
        for i=pageMult * listPageNumber + 1,pageMult * listPageNumber + pageMult,1 do
          if bothArray[1][i] ~= nil then
            text = " "
            if #bothArray[1][i].module.requirements ~= 0 then
              text = text .. "#"
            end
            if bothArray[1][i].hasDatabase ~= false then
              text = text .. "%"
            end
            if bothArray[1][i].hasServer ~= false then
              text = text .. "@"
            end
            displayList:addItem(bothArray[1][i].module.name .. text)
          end
        end
        if bothArray[1][1] == nil then
          moveRight.disabled = true
        else
          moveRight.disabled = false
        end
        for i=pageMult * listPageNumber2 + 1,pageMult * listPageNumber2 + pageMult,1 do
          if bothArray[2][i] ~= nil then
            text = " "
            if #bothArray[2][i].module.requirements ~= 0 then
              text = text .. "#"
            end
            if bothArray[2][i].hasDatabase ~= false then
              text = text .. "%"
            end
            if bothArray[2][i].hasServer ~= false then
              text = text .. "@"
            end
            downloadList:addItem(bothArray[2][i].module.name .. text)
          end
        end
        if bothArray[2][1] == nil then
          moveLeft.disabled = true
        else
          moveLeft.disabled = false
        end
        --Continue list update stuff
        --TODO: When adding page change, make sure if less are visible on a list, that it moves back a page
        if previousPage == listPageNumber then
          displayList.selectedItem = leftSelect
        else
          previousPage = listPageNumber
        end
        if previousPage2 == listPageNumber2 then
          downloadList.selectedItem = rightSelect
        else
          previousPage2 = listPageNumber2
        end
        workspace:draw()
      end
      local tempTable, hash = "", {}
      local worked,errored = compat.internet.request(download .. (settingTable.devMode and "getmodules/0" or "getmodules"),nil,{["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/64.0.3282.119 Safari/537.36"})
      if worked then
        tempTable = worked
        moduleTable = {}
        tempTable = JSON.decode(tempTable).modules
        moduleTable = tempTable
        hash = {}
        bothArray = {}
        bothArray[1],bothArray[2] = {}, {}
        for i=1,#moduleTable,1 do --FIXME: Might be the crasher
          moduleTable[i].module.requirements = moduleTable[i].module.requirements == nil and {} or split(moduleTable[i].module.requirements,",")
          if moduleTable[i].module.requirements ~= nil and settingTable.devMode and #moduleTable[i].module.requirements > 0 then
            for j = 1, #moduleTable[i].module.requirements,1 do
              moduleTable[i].module.requirements[j] = tostring(tonumber(moduleTable[i].module.requirements[j]) + 1)
            end
          end
          table.insert(bothArray[1],moduleTable[i])
        end
        layout:addChild(GUI.label(2,2,1,1,style.listPageLabel,loc.available))
        layout:addChild(GUI.label(41,2,1,1,style.listPageLabel,loc.downloading))
        layout:addChild(GUI.label(2,1,1,1,style.listPageLabel,loc.modulerequirementinfo))
        layout:addChild(GUI.panel(1,2,37,29,style.listPanel))
        displayList = layout:addChild(GUI.list(2, 3, 35, 27, 3, 0, style.listBackground, style.listText, style.listAltBack, style.listAltText, style.listSelectedBack, style.listSelectedText, false))
        layout:addChild(GUI.panel(40,2,37,29,style.listPanel))
        downloadList = layout:addChild(GUI.list(41, 3, 35, 27, 3, 0, style.listBackground, style.listText, style.listAltBack, style.listAltText, style.listSelectedBack, style.listSelectedText, false))
        moveRight = layout:addChild(GUI.button(15,31,16,1,style.bottomButton, style.bottomText, style.bottomSelectButton, style.bottomSelectText, loc.move .. " " .. loc.right))
        moveRight.onTouch = function() --This area manages the moving of data between lists for downloading or removal/no download. More complex due to checking requirements (required files being downloaded as well or removing files that require the file being removed.)
          local i = pageMult * listPageNumber + displayList.selectedItem
          table.insert(bothArray[2],bothArray[1][i])
          local removeId = bothArray[1][i].module.requirements
          table.remove(bothArray[1],i)
          local function removeRequirements(removeId)
            for _,value in pairs(removeId) do
              local buffer = 0
              for j=1,#bothArray[1],1 do
                if bothArray[1][j - buffer].module.id == tonumber(value) then
                  local be = bothArray[1][j].module.requirements
                  table.insert(bothArray[2],bothArray[1][j])
                  table.remove(bothArray[1],j)
                  buffer = buffer + 1
                  removeRequirements(be)
                end
              end
            end
          end
          removeRequirements(removeId)
          updateLists()
        end
        moveLeft = layout:addChild(GUI.button(56,31,16,1,style.bottomButton, style.bottomText, style.bottomSelectButton, style.bottomSelectText, loc.move .. " " .. loc.left))
        moveLeft.onTouch = function()
          local i = pageMult * listPageNumber2 + downloadList.selectedItem
          table.insert(bothArray[1],bothArray[2][i])
          local backup = bothArray[2][i].module.id
          table.remove(bothArray[2],i)
          local idList = {}
          local function removeRequirements(removeId)
            for j=1,#bothArray[2],1 do
              for _,value in pairs(bothArray[2][j].module.requirements) do
                if tonumber(value) == removeId then
                  table.insert(idList,bothArray[2][j].module.id)
                  removeRequirements(bothArray[2][j].module.id)
                end
              end
            end
          end
          removeRequirements(backup)
          for _,value in pairs(idList) do
            local buffer = 0
            for j=1,#bothArray[2],1 do
              if bothArray[2][j - buffer].module.id == value then
                table.insert(bothArray[1],bothArray[2][j - buffer])
                table.remove(bothArray[2],j - buffer)
                buffer = buffer + 1
              end
            end
          end --TODO: DOuble check this is all good.
          updateLists()
        end
        cancelButton = layout:addChild(GUI.button(80,5,16,1,style.bottomButton, style.bottomText, style.bottomSelectButton, style.bottomSelectText, loc.cancel))
        cancelButton.onTouch = function()
          layout:removeChildren()
          disabledSet()
        end
        downloadButton = layout:addChild(GUI.button(80,5,16,1,style.bottomButton, style.bottomText, style.bottomSelectButton, style.bottomSelectText, loc.setup .. " " .. loc.modules))
        downloadButton.onTouch = function()
          --TODO: Make this download all the necessary stuff cause I lazies.
          layout:removeChildren()
          userEditButton.disabled = true
          moduleInstallButton.disabled = true
          modulesLayout:removeChildren()
          layout:addChild(GUI.label(2,15,3,3,style.listPageLabel,loc.downloading .. " " .. #bothArray[2] .. " " .. loc.modules .. ". " .. loc.downloadinginfo))
          workspace:draw()
          local serverMods = {}
          local dbMods = {}
          for _,value in pairs(bothArray[2]) do
            if value.hasServer == true then
              table.insert(serverMods,value)
            end
            if value.hasDatabase == true then
              table.insert(dbMods,value)
            end
          end
          serverMods.debug = false
          local e,_,_,_,_,good = callModem(modemPort,"moduleinstall",crypt(ser.serialize(serverMods),settingTable.cryptKey))
          if e and crypt(good,settingTable.cryptKey,true) == "true" then --TEST: Does this successfully install everything
            if compat.fs.isDirectory(aRD .. "/Modules") then compat.fs.remove(aRD .. "/Modules") end
            compat.fs.makeDirectory(aRD .. "/Modules")
            for _,value in pairs(dbMods) do
              compat.fs.makeDirectory(modulesPath .. "modid" .. tostring(value.module.id))
              for i=1,#value.files,1 do
                if value.files[i].serverModule == false then
                  if settingTable.devMode == false then
                    compat.internet.download(value.files[i].url,modulesPath .. "modid" .. tostring(value.module.id) .. "/" .. value.files[i].path)
                  elseif value.files[i].devUrl ~= nil then
                    compat.internet.download(value.files[i].devUrl,modulesPath .. "modid" .. tostring(value.module.id) .. "/" .. value.files[i].path)
                  end
                end
              end
            end
            settingTable.moduleVersions = {}
            for _, value in pairs(bothArray[2]) do --Save versions to check for updates
              settingTable.moduleVersions[value.module.id] = value.module.version
            end
            compat.saveTable(settingTable,aRD .. "dbsettings.txt")
            --After done with downloading
            GUI.alert(loc.moduledownloadsuccess)
            window:removeChildren()
            window:remove()
            workspace:draw()
            workspace:stop()
          else
            GUI.alert(loc.sendservermodfail)
            window:removeChildren()
            window:remove()
            workspace:draw()
            workspace:stop()
          end
        end
        updateLists()
      else
        GUI.alert(errored)
        disabledSet()
      end
    end

    local function settingCallback()
      layout:removeChildren()
      userEditButton.disabled = true
      moduleInstallButton.disabled = true
      settingButton.disabled = true

      addVarArray = {["cryptKey"]=settingTable.cryptKey,["style"]=settingTable.style,["autoupdate"]=settingTable.autoupdate,["port"]=settingTable.port,["devMode"]=settingTable.devMode,["devModePre"]=settingTable.devMode}
      for key,value in pairs(configBuffer) do
        addVarArray[key] = value.default
      end
      layout:addChild(GUI.label(1,1,1,1,style.containerLabel,loc.style))
      local styleEdit = layout:addChild(GUI.input(15,1,16,1, style.containerInputBack,style.containerInputText,style.containerInputPlaceholder,style.containerInputFocusBack,style.containerInputFocusText, "", loc.style))
      styleEdit.text = settingTable.style
      styleEdit.onInputFinished = function()
        addVarArray.style = styleEdit.text
      end
      layout:addChild(GUI.label(1,3,1,1,style.containerLabel,loc.autoupdate))
      local autoupdatebutton = layout:addChild(GUI.button(15,3,16,1, style.containerButton,style.containerText,style.containerSelectButton,style.containerSelectText, loc.autoupdate))
      autoupdatebutton.switchMode = true
      autoupdatebutton.pressed = settingTable.autoupdate
      autoupdatebutton.onTouch = function()
        addVarArray.autoupdate = autoupdatebutton.pressed
      end
      layout:addChild(GUI.label(1,5,1,1,style.containerLabel,loc.port))
      local portInput = layout:addChild(GUI.input(15,5,16,1, style.containerInputBack,style.containerInputText,style.containerInputPlaceholder,style.containerInputFocusBack,style.containerInputFocusText, "", loc.inputtext))
      portInput.text = settingTable.port
      portInput.onInputFinished = function()
        addVarArray.port = tonumber(portInput.text)
      end
      layout:addChild(GUI.label(1,7,1,1,style.containerLabel,loc.developer))
      local developerbutton = layout:addChild(GUI.button(15,7,16,1, style.containerButton,style.containerText,style.containerSelectButton,style.containerSelectText, loc.toggle))
      developerbutton.switchMode = true
      developerbutton.pressed = settingTable.devMode
      developerbutton.onTouch = function()
        addVarArray.devMode = developerbutton.pressed
        if (addVarArray.devMode ~= addVarArray.devModePre) then
          GUI.alert(loc.devmodealert)
        end
      end
      layout:addChild(GUI.label(1,9,1,1,style.containerLabel,loc.cryptkey))
      local cryptInput = layout:addChild(GUI.input(15,9,16,1, style.containerInputBack,style.containerInputText,style.containerInputPlaceholder,style.containerInputFocusBack,style.containerInputFocusText, "", loc.style, true))
      cryptInput.text = "[NOT SHOWN]"
      cryptInput.onInputFinished = function()
        if cryptInput.text == "" then
          cryptInput.text = "[NOT SHOWN]"
        end
      end

      local dropInt = 11
      local setRay = {}
      for key,value in pairs(configBuffer) do
        layout:addChild(GUI.label(1,dropInt,1,1,style.containerLabel,value.label))
        if value.type == "bool" then
          setRay[key] = layout:addChild(GUI.button(15,dropInt,16,1, style.containerButton,style.containerText,style.containerSelectButton,style.containerSelectText, loc.enable))
          setRay[key].switchMode = true
          setRay[key].pressed = settingTable[key]
          setRay[key].onTouch = function()
            addVarArray[key] = setRay[key].pressed
          end
        elseif value.type == "int" then
          setRay[key] = layout:addChild(GUI.input(15,dropInt,16,1, style.containerInputBack,style.containerInputText,style.containerInputPlaceholder,style.containerInputFocusBack,style.containerInputFocusText, "", loc.inputtext))
          setRay[key].text = tostring(settingTable[key])
          setRay[key].onInputFinished = function()
            if (tonumber(setRay[key].text) ~= nil) then
              addVarArray[key] = tonumber(setRay[key].text)
            else
              setRay[key].text = tostring(addVarArray[key])
            end
          end
        else
          setRay[key] = layout:addChild(GUI.input(15,dropInt,16,1, style.containerInputBack,style.containerInputText,style.containerInputPlaceholder,style.containerInputFocusBack,style.containerInputFocusText, "", loc.inputtext))
          setRay[key].text = settingTable[key]
          setRay[key].onInputFinished = function()
            addVarArray[key] = setRay[key].text
          end
        end
        dropInt = dropInt + 2
      end

      
      local acceptButton = layout:addChild(GUI.button(15,dropInt,16,1, style.containerButton,style.containerText,style.containerSelectButton,style.containerSelectText, loc.submit))
      acceptButton.onTouch = function()
        if cryptInput.text ~= "[NOT SHOWN]" then
          addVarArray.cryptKey = split(cryptInput.text,",")
          for i=1,#addVarArray.cryptKey,1 do
            addVarArray.cryptKey[i] = tonumber(addVarArray.cryptKey[i])
          end
        else
          addVarArray.cryptKey = settingTable.cryptKey
        end
        local updateMeh = false
        if addVarArray.devMode ~= addVarArray.devModePre then
          updateMeh = true
          local e,_,_,_,_,good = callModem(modemPort,"devModeChange",crypt(ser.serialize({["devMode"] = addVarArray.devMode}),settingTable.cryptKey))
          if e and crypt(good,settingTable.cryptKey,true) == "true" then --TEST: Does server backup and stuff
            addVarArray.devModePre = nil
            settingTable = addVarArray
            if compat.fs.isDirectory(aRD .. "/Modules") then compat.fs.remove(aRD .. "/Modules") end
            compat.saveTable({},aRD .. "userlist.txt")
            GUI.alert(loc.serversuccess)
          else
            GUI.alert(loc.servermiss)
          end
        else
          addVarArray.devModePre = nil
          settingTable = addVarArray
          GUI.alert(loc.settingchangecompleted)
          local isUpdated = {}
          for key,value in pairs(configBuffer) do
            if value.server then
              isUpdated[key] = settingTable[key]
            end
          end
          local e,_,_,_,_,good = callModem(modemPort,"settingUpdate",crypt(ser.serialize(isUpdated),settingTable.cryptKey))
          if e and crypt(good,settingTable.cryptKey,true) == "true" then
            
          else
            GUI.alert(loc.dbchangesmiss)
          end
          updateServer()
        end
        compat.saveTable(settingTable,aRD .. "dbsettings.txt")
        layout:removeChildren()
        if modemPort ~= addVarArray.port or updateMeh then
          modem.close()
          modemPort = addVarArray.port
          modem.open(modemPort)
          window:remove()
          workspace:draw()
          workspace:stop()
        end
        disabledSet()
      end
      if online == false then
        styleEdit.disabled = true
        portInput.disabled = false
        autoupdatebutton.disabled = true
        for key,_ in pairs(setRay) do
          setRay[key].disabled = true
        end
        --addInput.disabled = true
        --remButton.disabled = true
      end
    end
    
    layout = window:addChild(GUI.container(20,1,window.width - 20, window.height))
    userEditButton = window:addChild(GUI.button(3,3,16,1,style.bottomButton, style.bottomText, style.bottomSelectButton, style.bottomSelectText, loc.edit .. " " .. loc.users))
    userEditButton.onTouch = beginUserEditing
    moduleInstallButton = window:addChild(GUI.button(3,5,16,1,style.bottomButton, style.bottomText, style.bottomSelectButton, style.bottomSelectText, loc.manage .. " " .. loc.modules))
    moduleInstallButton.onTouch = moduleInstallation
    settingButton = window:addChild(GUI.button(3,7,16,1,style.bottomButton, style.bottomText, style.bottomSelectButton, style.bottomSelectText, loc.settingsvar))
    settingButton.onTouch = settingCallback
    disabledSet()
  end
  module.close = function()

  end
  return module
end

local function runModule(module)
  window.modLayout:removeChildren()
  local modText = module.id ~= 0 and loc.badversionerror or loc.devmodulename
  modID = module.id
  for key,vare in pairs(settingTable.moduleVersions) do
    if key == module.id then
      modText = module.name .. " : " .. loc.version .. " " .. tostring(vare)
      break
    end
  end
  moduleLabel.text = modText
  module.onTouch()
  workspace:draw()
end

local function modulePress()
  local selected = modulesLayout.selectedItem
  if prevmod ~= nil then
    local p = prevmod.close()
    if p and settingTable.autoupdate then
      updateServer(p)
    end
  end
  selected = modulesLayout:getItem(selected)
  prevmod = selected.module
  runModule(selected.module)
end

----------Setup GUI
settingTable = compat.loadTable(aRD .. "dbsettings.txt")
if settingTable == nil then
  GUI.alert(loc.cryptalert)
  settingTable = {["cryptKey"]={1,2,3,4,5},["style"]="default.lua",["autoupdate"]=false,["port"]=1000,["externalModules"]={}}
  modem.open(syncPort)
  local e,_,_,_,_, f = callModem(syncPort,"syncport")
  if e then
    settingTable.port = tonumber(f)
  end
  modem.close(syncPort)
  compat.saveTable(settingTable,aRD .. "dbsettings.txt")
  online = false
end
if settingTable.style == nil then
  settingTable.style = "default.lua"
  compat.saveTable(settingTable,aRD .. "dbsettings.txt")
end
if settingTable.autoupdate == nil then
  settingTable.autoupdate = false
  compat.saveTable(settingTable,aRD .. "dbsettings.txt")
end
if settingTable.externalModules ~= nil then
  settingTable.externalModules = nil
  compat.saveTable(settingTable,aRD .. "dbsettings.txt")
end
if settingTable.moduleVersions == nil then
  settingTable.moduleVersions = {}
  compat.saveTable(settingTable,aRD .. "dbsettings.txt")
end
if settingTable.devMode == nil then --devMode has to do with installing modules. Causes you to install modules through the developer url setup by the creator
  isDevMode = true
  settingTable.devMode = false
  compat.saveTable(settingTable,aRD .. "dbsettings.txt")
end

if settingTable.devMode then
  GUI.alert(loc.devenabledalert)
end

modemPort = settingTable.port
if modem.isOpen(modemPort) == false then
  modem.open(modemPort)
end

style = compat.fs.readTable(stylePath .. settingTable.style)

workspace, window, menu = compat.system.addWindow(style.windowFill) --FIX IT

--window.modLayout = window:addChild(GUI.layout(14, 12, window.width - 14, window.height - 12, 1, 1))
window.modLayout = window:addChild(GUI.container(14, 12, window.width - 14, window.height - 12)) --136 width, 33 height if MineOS / 146, 36 if OpenOS

local function finishSetup()
  local updates, error = compat.internet.request(download .. "getversions", nil, {["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/64.0.3282.119 Safari/537.36"})
  if updates then
    updates = JSON.decode(updates).modules
    if settingTable.devMode == false then --Disable version checking for developer mode
      for _, upd in pairs(updates) do
        if settingTable.moduleVersions[upd.id] ~= nil and settingTable.moduleVersions[upd.id] ~= upd.version then
          GUI.alert("Some modules are out of date")
          break
        end
      end
    end
  else
    GUI.alert(loc.versionalert .. ": " .. error)
  end
  local dbstuff = {["update"] = function(table,force)
    if force or settingTable.autoupdate then
      updateServer(table)
    end
  end, ["save"] = function()
    compat.saveTable(userTable,"userlist.txt")
  end, ["crypt"]=function(str,reverse)
    return crypt(str,settingTable.cryptKey,reverse)
  end, ["send"]=function(wait,data,data2)
    if wait then
      return callModem(modemPort,data,data2)
    else
      modem.broadcast(modemPort,data,data2)
    end
  end, ["checkPerms"] = checkPerms, ["dataBackup"] = function(id, data) --save module stuff temporarily
    if data ~= nil then
      dataBuffer[id] = data
      return true
    else
      return dataBuffer[id]
    end
  end, ["checkConfig"] = function(cfg) --So users can check settings added to the dev settings module
    return settingTable[cfg]
  end}

  window:addChild(GUI.panel(1,11,12,window.height - 11,style.listPanel))
  modulesLayout = window:addChild(GUI.list(2,12,10,window.height - 13,3,0,style.listBackground, style.listText, style.listAltBack, style.listAltText, style.listSelectedBack, style.listSelectedText, false))
  local modulors = compat.fs.list(modulesPath)
  if modulors == nil then modulors = {} end
  modules = {}

  do --Contain dev module setup
    local object = modulesLayout:addItem("dev")
    local success, result = pcall(devMod, workspace, window.modLayout, loc, dbstuff, style, compat)
    if success then
      result.id = 0
      object.module = result
      object.isDefault = true
      object.onTouch = modulePress
      result.debug = debug
      table.insert(modules,result)
    else
      GUI.alert(loc.failedexecute .. " " .. loc.module .. " " .. "dev" .. ": " .. tostring(result))
    end
  end

  for i = 1, #modulors do
    local result, reason = loadfile(modulesPath .. modulors[i] .. "/Main.lua")
    if result then
      local success, result = pcall(result, workspace, window.modLayout, loc, dbstuff, style, compat)
      if success then
        local object = modulesLayout:addItem(result.name)
        if online then
          object.disabled = false
        else
          object.disabled = true
        end
        result.id = tonumber(string.sub(modulors[i],6,-2))
        object.module = result
        object.isDefault = false
        object.onTouch = modulePress
        result.debug = debug
        if result.config ~= nil then
          for key,value in pairs(result.config) do
            configBuffer[key] = value
          end
        end
        table.insert(modules,result)
        for i=1,#result.table,1 do
          table.insert(tableRay,result.table[i])
        end
      else
        GUI.alert(loc.failedexecute .. " " .. loc.module .. " " .. loc.infolder .. " " .. modulors[i] .. ": " .. tostring(result))
      end
    else
      GUI.alert(loc.failedload .. " " .. loc.module .. " " .. loc.infolder .. " " .. modulors[i].. ": " .. tostring(reason))
    end
  end

  --Take all configBuffer objects, check for existance, and create if necessary
  local saveProg = false
  local isServer = false
  for key,value in pairs(configBuffer) do
    if settingTable[key] == nil then
      settingTable[key] = value.default
      saveProg = true
      if value.server == true then
        isServer = true
      end
    end
  end
  if saveProg then
    if isServer then
      local isUpdated = {}
      for key,value in pairs(configBuffer) do
        if value.server then
          isUpdated[key] = settingTable[key]
        end
      end
      local e,_,_,_,_,good = callModem(modemPort,"settingUpdate",crypt(ser.serialize(isUpdated),settingTable.cryptKey))
      if e and crypt(good,settingTable.cryptKey,true) == "true" then
        compat.saveTable(settingTable,"dbsettings.txt")
      else
        GUI.alert(loc.dbnotreceivedrestart)
      end
    else
      compat.saveTable(settingTable,"dbsettings.txt")
    end
  end

  if online then
    local check,_,_,_,_,work = callModem(modemPort,"getquery",ser.serialize(tableRay))
    if check then
      work = ser.unserialize(crypt(work,settingTable.cryptKey,true))
      compat.saveTable(work.data,aRD .. "userlist.txt")
      userTable = work.data
    else
      GUI.alert(loc.userlistfailgrab)
      userTable = compat.loadTable(aRD .. "userlist.txt")
      if userTable == nil then
        GUI.alert(loc.nouserlistfound)
        window:remove()
        workspace:draw()
        workspace:stop()
      end
    end

    for i=1,#modules,1 do
      modules[i].init(userTable)
    end
  else
    modules[1].init(nil)
  end

  local contextMenu = compat.system.addContextMenu(menu,"File")
  contextMenu:addItem("Close").onTouch = function()
    window:remove()
    workspace:draw()
    workspace:stop()
    --os.exit()
  end

  --Database name and stuff and CardWriter
  window:addChild(GUI.panel(64,2,88,5,style.cardStatusPanel))
  if settingTable.devMode == false then
    window:addChild(GUI.label(66,2,3,1,style.cardStatusLabel,prgName .. " | " .. version))
  else
    window:addChild(GUI.label(66,2,3,1,style.cardStatusLabel,prgName .. " " .. loc.developermode .. " " .. " | " .. version))
  end
  if online then
    window:addChild(GUI.label(66,4,3,1,style.cardStatusLabel,loc.welcome .. " " .. usernamename))
  else
    window:addChild(GUI.label(66,4,3,1,style.cardStatusLabel,loc.currentlyoffline))
  end
  moduleLabel = window:addChild(GUI.label(66,6,3,1,style.cardStatusLabel,loc.no .. " " .. loc.module .. " " .. loc.selected))

  if settingTable.autoupdate == false and online then
    updateButton = window:addChild(GUI.button(40,5,16,1,style.bottomButton, style.bottomText, style.bottomSelectButton, style.bottomSelectText, loc.updateserver))
    updateButton.onTouch = function()
      updateServer()
    end
  end
end

local function signInPage()
  local username = window.modLayout:addChild(GUI.input(30,3,16,1, style.passInputBack,style.passInputText,style.passInputPlaceholder,style.passInputFocusBack,style.passInputFocusText, "", loc.username))
  local password = window.modLayout:addChild(GUI.input(30,6,16,1, style.passInputBack,style.passInputText,style.passInputPlaceholder,style.passInputFocusBack,style.passInputFocusText, "", loc.password,true,"*"))
  local submit = window.modLayout:addChild(GUI.button(30,9,16,1, style.passButton, style.passText, style.passSelectButton, style.passSelectText, loc.submit))
  local offlineMode = window.modLayout:addChild(GUI.button(30,21,16,1, style.passButton, style.passText, style.passSelectButton, style.passSelectText, loc.offlinemode))
  submit.onTouch = function()
    local check, work
    check,_,_,_,_,work,permissions = callModem(modemPort,"signIn",crypt(ser.serialize({["command"]="signIn",["user"]=username.text,["pass"]=password.text}),settingTable.cryptKey))
    if check then
      work = crypt(work,settingTable.cryptKey,true)
      if work == "true" then
        local pees = ser.unserialize(crypt(permissions,settingTable.cryptKey,true))
        permissions = {}
        for _,value in pairs(pees) do --issue
          permissions[value] = true
        end
        GUI.alert(loc.signinsuccess)
        usernamename, userpasspass = username.text,password.text
        window.modLayout:removeChildren()
        local mep
        check,_,_,_,_,work,mep = callModem(modemPort,"integritySync",crypt(ser.serialize({["devMode"]=settingTable.devMode}),settingTable.cryptKey))
        if check then
          work = crypt(work,settingTable.cryptKey,true)
          if work == "true" then
            mep = ser.unserialize(crypt(mep,settingTable.cryptKey,true))
            if mep.good == true then
              finishSetup()
            else
              GUI.alert(loc.integviolation,mep.text,loc.integviolation2)
              window:remove()
              workspace:draw(true)
              workspace:stop()
            end
          else
            GUI.alert(loc.integfail)
          end
        else
          GUI.alert(loc.integfailcon)
        end
        finishSetup()
      else
        GUI.alert(loc.baduserpass)
      end
    else
      GUI.alert(loc.noserverconfirm)
    end
  end
  offlineMode.onTouch = function()
    online = false
    modem.close()
    window.modLayout:removeChildren()
    finishSetup()
  end
end

if online then
  signInPage()
else
  finishSetup()
end

workspace:draw()
workspace:start()
