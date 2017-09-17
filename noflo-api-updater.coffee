#!/usr/bin/env coffee
fs = require 'fs'
path = require 'path'
indentString = require 'indent-string'
cs = require 'coffee-script'

indent = (indent) ->
  string = ""
  for i in [0...indent]
    string += "  "
  string

#
# @TODO: could use args[0] of wirepattern to name first port if it isn't `data, payload, input` ?
#
# @TODO: with in port `measurement` this would use
# , (payload, groups, out, callback) ->
#    unless payload?.measurement?
#
# @TODO: if using wirepattern
# `(input, groups, out, callback) -> console.log input`
# should replace `input` or whatever name of var is with the 1 required `in`
#
# @TODO: option to just convert in/out ports
# @TODO: convert stateful components which set things for param ports
#
class WirePatternComponentUpdater
  constructor: (@source) ->

  update: ->
    @updateWirePattern @source

  getFilteredPorts: (ports) ->
    filteredPorts = {}
    for port, value of ports
      continue if port is 'ports'
      continue if typeof value isnt 'object'
      continue unless value?
      filteredPorts[port] = value.options
    filteredPorts

  portsToString: (ports) ->
    portsStr = ""
    for port, options of ports
      continue if port is 'ports'
      portsStr += indent(2) + port + ":\n"
      for option, value of options
        continue if option in ['buffered', 'required', 'triggering']
        continue if option is 'control' and value is false
        if typeof value is 'string'
          value = "'#{value}'"
        portsStr += indent(3) + option + ": " + value + "\n"
    portsStr

  preconditionGet: (source, ins, outs, inPorts, params) ->
    precondition = ""
    getDataString = "["
    getPortData = []
    mustHave = []

    for port in ins
      mustHave.push port
      getPortData.push port

    if params?
      for param in params
        inPorts[param].control = true
        if inPorts[param].required
          mustHave.push param
        getPortData.push param

    # add to the [vars]
    if getPortData.length > 1
      for port in getPortData
        # because we cannot use reserved words
        port = 'ins' if port is 'in'
        getDataString += port + ', '
      # remove trailing comma + space
      getDataString = getDataString.slice(0, -2) + "]"
    else
      getDataString = getPortData[0]
      # because we cannot use reserved words
      if getDataString is 'in'
        getDataString = 'ins'

    getDataString += " = input.getData "
    for port in getPortData
      getDataString += "'#{port}', "
    # remove trailing comma + space
    getDataString = getDataString.slice(0, -2)

    # --- PRECONDITION ---
    precondition = 'return unless input.has '
    for must in mustHave
      precondition += "'#{must}', "
    precondition += "(ip) -> ip.type is 'data'"

    [precondition, getDataString]

  replaceInputOutDone: (wirePatternCode, wirepattern, outs, ins, args) ->
    # if args[0] in ins
    # payloadRe = new RegExp(args[0], "gm")
    # if payloadRe.test wirepattern
    #   wirePatternCode = wirePatternCode.replace new RegExp(args[0] + '\.', "gm"), ''
    if /(input, )/.test wirepattern
      wirePatternCode = wirePatternCode.replace /input\./g, ''
    if /(data, )/.test wirepattern
      wirePatternCode = wirePatternCode.replace /data\./g, ''

    # @TODO: is a problem...
    # replace argument of wirepattern with first in port
    # if args[0] isnt 'data' or 'input'
    inPort = if ins[0] is 'in' then 'ins' else ins[0]
    wirePatternCode = wirePatternCode.replace new RegExp(args[0], "gm"), inPort

    if outs.length is 1
      wirePatternCode = wirePatternCode.replace /out\.send/g, 'output.send ' + outs[0] + ':'
      wirePatternCode = wirePatternCode.replace /out\.disconnect/g, "output.ports.#{outs[0]}.disconnect"
    else
      if /outs.(.*)\.send/gmi.test wirePatternCode
        wirePatternCode = wirePatternCode.replace /outs.(.*)\.send/gmi, "output.ports.$1.send"
        wirePatternCode = wirePatternCode.replace /outs.(.*)\.disconnect/gmi, "output.ports.$1.disconnect"
      else if /out.(.*)\.send/gmi.test wirePatternCode
        wirePatternCode = wirePatternCode.replace /out.(.*)\.send/gmi, "output.ports.$1.send"
        wirePatternCode = wirePatternCode.replace /out.(.*)\.disconnect/gmi, "output.ports.$1.disconnect"

    # replace `c.params.name` with `name`
    wirePatternCode = wirePatternCode.replace /(c\.params\.([a-zA-Z0-9]*))/gmi, '$2'
    wirePatternCode = wirePatternCode.replace /done/g, 'output.done'
    wirePatternCode = wirePatternCode.replace /callback/g, 'output.done'

    wirePatternCode

  getWirePatternProcArguments: (wirepattern) ->
    args = /(?:, \()(.*)(:?\) ->)/.exec wirepattern
    args[1].split ','

  getWirePatternProperties: (wirepattern, config) ->
    processConfigInOut = (item) ->
      return null unless item?
      return item if Array.isArray item
      return [item]

    ins = processConfigInOut config.in
    outs = processConfigInOut config.out
    params = processConfigInOut config.params
    [ins, outs, params]

  replaceReturnC: (source) ->
    source.replace /(  c$)/gmi, ''

  forwardGroups: (ins, outs, params) ->
    forwardGroupsObj = {}
    for inPort in ins
      forwardGroupsObj[inPort] ?= []
      for outPort in outs
        forwardGroupsObj[inPort].push outPort

    if params?
      for inPort in params
        forwardGroupsObj[inPort] ?= []
        for outPort in outs
          forwardGroupsObj[inPort].push outPort

    # format it
    forwardGroups = 'c.forwardBrackets = \n'
    for port, value of forwardGroupsObj
      for v, i in value
        value[i] = "'#{v}'"
      value = value.join(', ')
      forwardGroups += indent(1) + "#{port}: [#{value}]\n"

    forwardGroups

  updateWirePattern: (source) ->
    # make sure it has `wirepattern`
    regexWP = /(noflo.helpers.WirePattern)((.|\n)*)/
    unless regexWP.test source
      console.error "(!) No WirePattern found"
      return source

    # --- EVERYTHING BEFORE GETCOMPONENT ---
    beforeComponent = (/^((.|\n)*?)(?=exports)/.exec source)[1]

    # --- COMPILING ---
    # hijack `WirePattern` so it adds `config` to the
    # remove the requires so it can be `eval`d
    # compile so it can be loaded to get actual ports without regex
    # withoutReqs = source.replace /([a-zA-Z0-9]+ = require.*)/gmi, ""
    withoutReqs = source.replace beforeComponent, ""
    withoutReq = "noflo = require 'noflo' \n"
    withoutReq += "noflo.helpers.WirePattern = (comp, config, proc) -> comp.config = config; return comp; \n"
    withoutReq += withoutReqs
    compiled = cs.compile withoutReq, bare: true
    component = eval compiled
    c = component()

    # --- PORTS & WP PARAMS ---
    inPorts = @getFilteredPorts c.inPorts
    outPorts = @getFilteredPorts c.outPorts
    source = @replaceReturnC source

    wirepattern = (regexWP.exec source)[0]
    wirePatternCode = (/(?:->)((.|\n)*)/.exec wirepattern)[1]
    args = @getWirePatternProcArguments wirepattern
    [ins, outs, params] = @getWirePatternProperties wirepattern, c.config
    [precondition, getDataString] = @preconditionGet source, ins, outs, inPorts, params
    wirePatternCode = @replaceInputOutDone wirePatternCode, wirepattern, outs, ins, args

    if c.config.forwardGroups
      forwardGroups = @forwardGroups ins, outs, params

    # ---- OUTPUT ---
    # if it has only 1 output.send, do output.sendDone?
    # or if it doesn't have it `indexOf` then say it in the logs
    # if it has neither, add it anyway?

    inPortsStr = @portsToString inPorts
    outPortsStr = @portsToString outPorts
    inPortsStr = indentString inPortsStr, 2
    outPortsStr = indentString outPortsStr, 2

    output = ""
    output += beforeComponent
    output += "exports.getComponent ->\n"
    output += indent(1) + "c = new noflo.Component\n"

    output += indent(2) + "icon: '#{c.icon}'\n" if c.icon if c.icon? and c.icon isnt ""
    output += indent(2) + "description: '#{c.description}'\n" if c.description? and c.description isnt ""
    output += indent(2) + "ordered: true\n" if c.config.ordered is true
    output += indent(2) + "ordered: false\n" if c.config.ordered is false

    output += indent(2) + "inPorts:\n"
    output += inPortsStr

    output += indent(2) + "outPorts:\n"
    output += outPortsStr + "\n"

    output += indentString forwardGroups, 2 if forwardGroups?

    output += indent(1) + 'c.process (input, output) ->' + "\n"
    output += indent(2) + precondition + "\n"
    output += indent(2) + getDataString + "\n"
    output += wirePatternCode

    unless output.includes('output.done') or output.includes('output.sendDone')
      console.log 'needs to call `done`'

    @source = output
    return output

# ------

class ComponentUpdater
  constructor: (@source) ->
    @name = ''
    @class = ''
    @inPorts = {}
    @outPorts = {}
    @listeners = {}

  update: ->
    # Remove the old exports.getComponent
    @source = @source.replace /\nexports.getComponent\s*=.+?(\n|$)/, "\n  return component\n"
    # Replace class with a noflo.Component instance
    @source = @source.replace /^class\s+(\w+)\s+extends\s+noflo\.((Async)?Component)\s*$/m, (str, name, cls) =>
      @name = name
      @class = cls
      if @class is 'AsyncComponent'
        console.log "(!) #{name}: AsyncComponent is deprecated"
      return """
      exports.getComponent = ->
        component = new noflo.#{cls}

      """
    # Rebuild the constructor
    @source = @source.replace /constructor:\s*->\s*\r?\n([\s\S]+?)(\r?\n {2}\S|$)/, (str, constructor, postfix) =>
      return @updateConstructor(constructor) + postfix
    # Replace '@' with 'component.'
    @source = @source.replace /(\W)@(\w+)/g, '$1component.$2'
    # Class methods to object methods
    @source = @source.replace /(\n\s{2})(\w+):/g, '$1component.$2 ='
    return @source

  updateConstructor: (constructor) ->
    # Remove old ports definition and grab their data
    re = /(?:^|\n) {4}@inPorts\s*=\s*\n([\s\S]+?)(\r?\n {4}\S|$)/
    unless re.test constructor
      console.error "(!) No old-style @inPorts found in #{@name}, leaving constructor as is"
      # Outdent the leftover
      constructor = constructor.replace /(^|\n)( {2}) {2}/g, '$1$2'
      return constructor
    constructor = constructor.replace /(?:^|\n) {4}@inPorts\s*=\s*\r?\n([\s\S]+?)(\r?\n {4}\S|$)/, (str, body, postfix) =>
      @grabInPorts body
      return postfix
    constructor = constructor.replace /(?:^|\n) {4}@outPorts\s*=\s*\r?\n([\s\S]+?)(\r?\n {4}\S|$)/, (str, body, postfix) =>
      @grabOutPorts body
      return postfix
    # Remove old event listeners and grab their contents
    re = /(?:^|\n) {4}@inPorts\.(\w+)\.on\s+(["']([\w]+)["']),\s*(.*?)\s*[=-]>\s*(\r?\n {6}([\s\S]+?))?(\r?\n {4}\S|\s*$)/
    while m = re.exec constructor
      @grabListener m[1], m[3], m[4], m[6]
      constructor = constructor.replace m[0], m[7]
    # Outdent the leftover
    constructor = constructor.replace /(^|\n)( {2}) {2}/g, '$1$2'
    # Compile a new constructor
    return @makePorts() + constructor

  grabInPorts: (body) ->
    portPattern = /(\w+)\s*:\s*new\s+noflo.Port\s*(['"](\w+)['"])?/g
    while m = portPattern.exec body
      datatype = if m[3] then m[3] else 'all'
      @inPorts[m[1]] =
        datatype: datatype

  grabOutPorts: (body) ->
    portPattern = /(\w+)\s*:\s*new\s+noflo.Port\s*(['"](\w+)['"])?/g
    while (m = portPattern.exec body) isnt null
      datatype = if m[3] then m[3] else 'all'
      @outPorts[m[1]] =
        datatype: datatype

  grabListener: (port, evt, args, body) ->
    @listeners[port] = {} unless port of @listeners
    m = /\((@)?(\w+)\)/.exec args
    body = '' if body is undefined
    if m
      re = RegExp '([^\\w@]|^)' + m[2] + '\\b'
      body = body.replace re, '$1payload'
      if m[1]
        prefix = "component.#{m[2]} = payload"
        body = if body then prefix + "\n      " + body else prefix
    body = body.replace /^\s+/, ''
    @listeners[port][evt] = body

  makePorts: ->
    code = ''
    process = ''
    for name, port of @inPorts
      code += '  ' if code.length > 0
      code += "component.inPorts.add '#{name}',\n    datatype: '#{port.datatype}'\n"
      if name of @listeners
        if Object.keys(@listeners[name]).length is 1
          evt = Object.keys(@listeners[name])[0]
          body = @listeners[name][evt]
          process += "
                if input.port.name is '#{name}' and input.ip.type is '#{evt}'
                  payload = input.getData '#{name}'
                  #{body}
                  # FIXME send output data correctly
                  return output.sendDone()\n
          "
        else
          process += """
            if input.port.name is '#{name}'
              ip = input.get '#{name}'
              payload = ip.data
              switch ip.type
              """
          for evt, body of @listeners[name]
            # Increase body indent
            body = body.replace /(^|\n)( {2})/g, '$1$2  '
            process += "      when '#{evt}'\n        #{body}\n"
      else
        code += "\n"
    for name, port of @outPorts
      code += "  component.outPorts.add '#{name}',\n    datatype: '#{port.datatype}'\n"
    if process isnt ''
      code += "  component.process (input, output) ->\n    #{process}\n"
    return code

backupFile = (filePath, source) ->
  dirname = path.dirname filePath
  filename = path.basename filePath
  backupPath = "#{dirname}/backup/#{filename}"
  if not fs.existsSync "#{dirname}/backup"
    fs.mkdirSync "#{dirname}/backup"
  if not fs.existsSync backupPath
    fs.writeFileSync backupPath, source, 'utf8'

updateFile = (filePath, pretend) ->
  fs.readFile filePath, 'utf8', (err, source) ->
    if err
      console.error "(!) Could not read file:", err
      return

    if /(noflo.helpers.WirePattern)((.|\n)*)/.test source
      updater = new WirePatternComponentUpdater source
    else
      updater = new ComponentUpdater source

    updated = updater.update()
    if pretend
      console.log "(i) Updated source for", filePath
      console.log updated
    else
      backupFile filePath, source
      fs.writeFile filePath, updated, 'utf8', (err) ->
        if err
          console.error "(!) Could not read file:", err
        else
          console.log "(+) Updated: ", filePath

switch process.argv.length
  when 4
    mode = process.argv[2]
    filePath = process.argv[3]
  when 3
    mode = false
    filePath = process.argv[2]
  else
    console.log "Format: noflo-api-updater [--pretend] <path-to-components>"
    process.exit 0

if !fs.existsSync filePath
  console.error "(!) Path not found: ", filePath
  process.exit 1

pretend = mode is '--pretend'
isCoffee = /\.coffee$/

if isCoffee.test filePath
  updateFile filePath, pretend
else
  fs.readdir filePath, (err, files) ->
    for file in files
      updateFile "#{filePath}/#{file}", pretend if isCoffee.test file
