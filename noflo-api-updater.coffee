#!/usr/bin/env coffee
fs = require 'fs'

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
    for name, port of @inPorts
      code += '  ' if code.length > 0
      code += "component.inPorts.add '#{name}', datatype: '#{port.datatype}'"
      if name of @listeners
        if Object.keys(@listeners[name]).length is 1
          evt = Object.keys(@listeners[name])[0]
          body = @listeners[name][evt]
          code += ", (event, payload) ->\n    if event is '#{evt}'\n      #{body}\n"
        else
          code += ", (event, payload) ->\n    switch event\n"
          for evt, body of @listeners[name]
            # Increase body indent
            body = body.replace /(^|\n)( {2})/g, '$1$2  '
            code += "      when '#{evt}'\n        #{body}\n"
      else
        code += "\n"
    for name, port of @outPorts
      code += "  component.outPorts.add '#{name}', datatype: '#{port.datatype}'\n"
    return code

updateFile = (path, pretend) ->
  fs.readFile path, 'utf8', (err, source) ->
    if err
      console.error "(!) Could not read file:", err
      return
    updater = new ComponentUpdater source
    updated = updater.update()
    if pretend
      console.log "(i) Updated source for", path
      console.log updated
    else
      fs.writeFile path, updated, 'utf8', (err) ->
        if err
          console.error "(!) Could not read file:", err
        else
          console.log "(+) Updated: ", path

switch process.argv.length
  when 4
    mode = process.argv[2]
    path = process.argv[3]
  when 3
    mode = false
    path = process.argv[2]
  else
    console.log "Format: noflo-api-updater [--pretend] <path-to-components>"
    process.exit 0

if !fs.existsSync path
  console.error "(!) Path not found: ", path
  process.exit 1

pretend = mode is '--pretend'
isCoffee = /\.coffee$/

if isCoffee.test path
  updateFile path, pretend
else
  fs.readdir path, (err, files) ->
    for file in files
      updateFile "#{path}/#{file}", pretend if isCoffee.test file
