# code to wire the evolution code to the demo page
initializationParameters =
  pause: [ 10, 0, 1000, 'minimum pause between ticks' ]
  maxDistance: [ 60, 30, 100, 'maximum distance an organism can see' ]
  initialCreatures:
    stones:
      num: [ 40, 0, 100 ]
    plants:
      num: [ 100, 10, 500 ]
      init:
        bodyColor: '#ffcb0c'
        radius: [ 4, 2, 20, 'plant size' ]
    herbivores:
      num: [ 8, 0, 100 ]
      init:
        bodyColor: '#2b4dcb'
        radius: [ 5, 2, 20, 'body size' ]
    carnivores:
      num: [ 40, 0, 100 ]
      init:
        bodyColor: '#ec2200'
        radius: [ 6, 2, 20, 'body size' ]

# some jQuery-esque convenience functions
byId = (id) -> document.getElementById(id)
byClass = (cz) ->
  wonky = document.getElementsByClassName cz
  wonky.item(i) for i in [0...wonky.length]
# assign or augment an event handler on an element
# handler is augmented unless last parameter is true
onEvent = ( type, e, f, clear ) ->
  name = 'on' + type
  if clear
    e[name] = f
  else
    old = e[name]
    if old
      f = (e) -> f(e); old(e)
    e[name] = f
trimNum = (n) -> parseFloat n.toPrecision(3)
decamelize = (str) ->
  str = str.replace /([a-z])([A-Z])/g, (t) -> t.charAt(0) + ' ' + t.charAt(1).toLowerCase()
titleize = (str) ->
  str.replace /\b[a-z]\w*/g, (s) -> s.charAt(0).toUpperCase() + s.substr(1).toLowerCase()
text = (t) ->
  document.createTextNode(t)
intFormat = (int) ->
  ar = ( '' + int ).split('').reverse()
  ar2 = []
  for v, i in ar
    ar2.push ',' if i && !( i % 3 )
    ar2.push v
  ar2.reverse().join ''
create = (tag, cz, id) ->
  e = document.createElement(tag)
  e.setAttribute( 'class', cz ) if cz?
  e.id = id if id?
  e

chartType = 'about'
[ u, makeCharts, loaded, munged ] = [ null, false, false, false ]
convertParams = (obj=initializationParameters) ->
  copy = {}
  for k,v of obj
    if v instanceof Array
      copy[k] = v[0]
    else if typeof v == 'object'
      copy[k] = convertParams v
    else
      copy[k] = v
  copy
makeInputs = (obj=initializationParameters, parent=byId('options')) ->
  for k,v of obj
    div = create 'div', 'indenter'
    h = create 'div', 'param-header'
    h.innerHTML = decamelize k
    div.appendChild h
    parent.appendChild div
    if v instanceof Array
      makeSlider k, obj, div
    else if /color/i.test k
      makeColorPicker k, obj, div
    else if typeof v == 'boolean'
      makeCheckbox k, obj, div
    else
      makeInputs v, div
makeColorPicker = (label, object, parent) ->
  color = object[label]
  s = create 'input'
  s.type = 'color'
  s.value = color
  h = parent.firstChild
  h.appendChild text(' ')
  h.appendChild s
  sp = create 'span'
  sp.innerHTML = color
  sp.style.fontWeight = 'normal'
  h.appendChild text(' ')
  h.appendChild sp
  s.onchange = ->
    object[label] = s.value
    sp.innerHTML = s.value
makeCheckbox = (label, obj, parent) ->
makeSlider = (label, object, parent) ->
  values = object[label]
  s = create 'input'
  s.type = 'range'
  s.value = values[0]
  s.min = values[1]
  s.max = values[2]
  s.title = d if d = values[3]
  s.step = 1
  sp = create 'span', 'param-value'
  sp.innerHTML = values[0]
  parent.appendChild s
  parent.appendChild sp
  s.onchange = ->
    sp.innerHTML = s.value
    values[0] = Number.parseInt s.value
madeGeneCharts = false
chartDiv = ( tab, id ) ->
  div = create 'div', 'chart', id
  tab.appendChild div
  id
makeUniverse = ->
  p = convertParams()
  p.callback = collectData
  u = new Universe 'universe', p
  setImages()
  unless madeGeneCharts
    for type in [ 'plant', 'herbivore', 'carnivore' ]
      tab = byId "#{type}-chart"
      charts = evoData.charts[type] = {}
      id = chartDiv tab, "#{type}-babies"
      charts.babies =
        id:        id
        type:      'interval'
        htitle:    'Time (ticks)'
        vtitle:    'Offspring per individual'
        collector: statCollector titleize(type), (d) -> d.babies
        rows:      []
      id = chartDiv tab, "#{type}-age"
      charts.age =
        id:        id
        type:      'interval'
        htitle:    'Time (ticks)'
        vtitle:    'Age (ticks)'
        collector: statCollector titleize(type), (d) -> u.tick - d.tick
        rows:      []
      for gene, v of u.urThing(type).genes
        id = chartDiv tab, "#{type}-#{gene}"
        charts[gene] = geneChartSpec type, gene, id
evoData =
  generation: 0
  charts:
    all:
      Population:
        id: 'chart'
        htitle: 'Time (ticks)'
        vtitle: 'Num. individuals'
        collector: (stats, rows) ->
          counts = Plant: 0, Herbivore: 0, Carnivore: 0
          counts[description.type] += 1 for description in stats
          row = [ evoData.generation, counts.Plant, counts.Herbivore, counts.Carnivore ]
          rows.push row
        names: [ 'Plant', 'Herbivore', 'Carnivore' ]
        colors: [
            -> u.urThing('plant').bodyColor
            -> u.urThing('herbivore').bodyColor
            -> u.urThing('carnivore').bodyColor
          ]
        rows: []
      Energy:
        id: 'energy'
        htitle: 'Time (ticks)'
        vtitle: 'Net energy embodied by individuals'
        collector: (stats, rows) ->
          counts = Plant: 0, Herbivore: 0, Carnivore: 0
          counts[description.type] += description.hp for description in stats
          row = [ evoData.generation, counts.Plant, counts.Herbivore, counts.Carnivore ]
          rows.push row
        names: [ 'Plant', 'Herbivore', 'Carnivore' ]
        colors: [
            -> u.urThing('plant').bodyColor
            -> u.urThing('herbivore').bodyColor
            -> u.urThing('carnivore').bodyColor
          ]
        rows: []
clearEvoData = ->
  evoData.generation = 0
  rowClearer = (obj) ->
    return false unless obj?
    if obj.rows instanceof Array
      obj.rows = []
    else
      for k, v of obj
        if typeof v == 'object'
          rowClearer v
  rowClearer evoData.charts
statCollector = ( type, selector ) ->
  ( stats, rows ) ->
    values = []
    values.push selector(d) for d in stats when d.type == type
    [ min, max, mean, median ] = [ 0, 0, 0, 0 ]
    if values.length
      values.sort (a,b) -> a - b
      min = values[0]
      max = values[ values.length - 1 ]
      mean += v for v in values
      mean /= values.length
      if values.length % 2
        median = values[ Math.floor(values.length/2) ]
      else
        i = values.length / 2
        median = ( values[i] + values[i - 1] ) / 2
      rows.push [ evoData.generation, trimNum(median), trimNum(mean), trimNum(min), trimNum(max) ]
geneChartSpec = ( type, gene, id ) ->
  title = type.charAt(0).toUpperCase() + type.substr(1)
  original = u.urThing(type).genes[gene][0]
  original = original() if typeof original == 'function'
  {
    id:        id
    type:      'interval'
    htitle:    'Time (ticks)'
    vtitle:    'Value of gene'
    original:  original
    collector: statCollector title, (d) -> d.genes[gene]
    rows:      []
  }
collectData = ->
  evoData.generation += 1
  byId('ticks').innerHTML = intFormat evoData.generation
  byId('created').innerHTML = intFormat u.thingsCreated()
  byId('current').innerHTML = intFormat u.currentThings()
  byId('plant-count').innerHTML = intFormat u.plantCount()
  byId('animal-count').innerHTML = intFormat u.animalCount()
  byId('herbivore-count').innerHTML = intFormat u.herbivoreCount()
  byId('carnivore-count').innerHTML = intFormat u.carnivoreCount()
  if loaded and not munged
    e.remove() for e in byClass 'wait'
    munged = true
  stats = u.describe()
  for tab, specs of evoData.charts
    for title, details of specs
      details.collector stats, details.rows
  if loaded and ( u.done or not u.running )
    drawChart e.innerHTML for e in sibs
    if u.done
      byId('start').innerHTML = 'start'
      byId('stop').style.display = 'none'
      u.prime()
      fiddled = true
  else if makeCharts
    drawChart()
fiddled = false
start = ->
  if u && u.running
    u.stop()
    evoData.generation = 0
    clearCharts()
    u.erase()
  byId('stop').style.display = 'inline'
  byId('clear').style.display = 'inline'
  byId('start').innerHTML = 'restart'
  makeUniverse() unless fiddled
  fiddled = false
  u.run()
  byId('stop').innerHTML = 'stop'
  false
stop = ->
  return unless u
  element = byId 'stop'
  if u.running
    u.stop()
    element.innerHTML = 'resume'
  else
    u.run()
    element.innerHTML = 'stop'
  false
clear = ->
  oldCallback = u.callback || ->
  u.callback = ->
    oldCallback()
    clearEvoData()
    u.stop()
    u.erase()
    makeUniverse()
    byId('stop').style.display = 'none'
    e = byId 'start'
    e.style.display = 'inline'
    e.innerHTML = 'start'
    byId('clear').style.display = 'none'
  u.callback() unless u.running
  false
trimData = (data, size) ->
  return data if data.length < size
  results = []
  results.push data[i] for i in [data.length - size...data.length]
  results
clearCharts = ->
  for type, subtype of evoData.charts
    for title, specs of subtype
      id = specs.id
      chart.clearChart() if chart = specs.chart
      specs.rows = []
drawChart = (ct=chartType)->
  return if ct == 'options' or ct == 'about'
  for title, specs of evoData.charts[ct] || {}
    rows = trimData specs.rows, 500
    return unless rows.length && rows[0].length
    id     = specs.id
    chart  = specs.chart
    htitle = specs.htitle
    vtitle = specs.vtitle
    width  = specs.width || 1000
    height = specs.height || 400
    data = new google.visualization.DataTable()
    data.addColumn 'number', 'X'
    options =
      title: titleize decamelize(title)
      width: width
      height: height
      hAxis:
        title: htitle
      vAxis:
        title: vtitle
    if specs.type == 'interval'
      data.addColumn 'number', 'values'
      if specs.original?
        delta = rows[ rows.length - 1 ][1] - specs.original
        options.title = "Gene: #{options.title} (delta: #{trimNum delta})"
      ids = []
      for i in [2...5]
        data.addColumn id: "i#{i}", type: 'number', role: 'interval'
      options.interval =
            i2: style: 'line', color:'green' # mean
            i3: style: 'line', color:'black' # min
            i4: style: 'line', color:'red' # max
      options.lineWidth = 2
      options.legend    = 'none'
    else
      names  = specs.names
      colors = specs.colors
      if colors
        for c, i in colors
          colors[i] = c() if typeof c == 'function'
        options.colors = colors
      data.addColumn 'number', n for n in names
    data.addRows rows
    if chart
      chart.clearChart()
    else
      specs.chart = chart = new google.visualization.LineChart byId(id)
    chart.draw data, options
tabs = []
sibs = []
regTabs = {}
restoreAbout = ( ->
  t = byId 'tabs'
  c = t.firstChild
  while c = c.nextSibling
    break if c.innerHTML == 'about'
  -> tabClicked(c)
  )()
tabClicked = (c) ->
  return if c.className == 'active'
  s.classList.remove('active') for s in sibs
  c.classList.add 'active'
  t.style.display = 'none' for t in tabs
  chartType = c.innerHTML
  if c.classList.contains 'reg'
    makeCharts = false
    content = byId chartType
    content.style.display = 'table'
  else
    byId( chartType + '-chart' ).style.display = 'block'
    tryLoad()
tryLoad = (making=true) ->
  try
    makeCharts = making
    unless loaded
      google.load 'visualization', '1', packages: ['corechart']
      google.setOnLoadCallback drawChart
      loaded = true
  catch e
    alert "Could not make charts: #{e}" unless regTabs[chartType]
    makeCharts = false
    loaded = false
    restoreAbout()
geometries = {}
setImages = ->
  for type in [ 'plant', 'stone', 'herbivore', 'carnivore' ]
    selector = "img." + type
    images = document.querySelectorAll( "img." + type )
    if images.length
      [ data, width, height, x, y ] = geometries[type] = u.imageFor type
      for i in [0...images.length]
        img = images[i]
        img.src = data
        img.width = width
        img.height = height

crosshairCursor = (color='black') ->
  c = create 'canvas'
  c.setAttribute 'width', 16
  c.setAttribute 'height', 16
  ctx = c.getContext '2d'
  ctx.strokeStyle = color
  ctx.beginPath()
  ctx.arc 8, 8, 6, 0, Math.PI * 2
  ctx.stroke()
  ctx.beginPath()
  ctx.moveTo 8, 0
  ctx.lineTo 8, 16
  ctx.stroke()
  ctx.beginPath()
  ctx.moveTo 0, 8
  ctx.lineTo 16, 8
  ctx.stroke()
  c.toDataURL 'image/png', 1.0

( ->
  makeInputs()
  div = byId 'tab-div'
  while div = div.nextSibling
    tabs.push div if div.nodeType == 1
  child = byId('tabs').firstChild
  while child = child.nextSibling
    if child.nodeType == 1 && child.className != 'buffer'
      sibs.push child
      regTabs[child.innerHTML] = true if child.classList.contains 'reg'
      firstClick = child if child.innerHTML == 'about'
      child.onclick = ( (c) -> 
        -> tabClicked c
        )(child)
      cd = byId "#{child.innerHTML}-chart"
      if cd
        p = create 'p', 'wait'
        p.appendChild text('Charts will appear here when the simulation starts provided Google charts can be loaded.')
        if cd.firstChild
          cd.insertBefore p, cd.firstChild
        else
          cd.appendChild p
  firstClick.click()
  goodWidth = byId('tabs').clientWidth
  e.style['max-width'] = goodWidth for e in byClass('table-y')
  tryLoad(false)
  makeUniverse()
  onEvent 'click', byId('clear-cursor'), (e) ->
    document.body.style.cursor = 'auto'
    onEvent 'click', byId('universe'), (->), true
  onEvent 'click', byId('highlight'), (e) ->
    document.body.style.cursor = 'crosshair'
    onEvent( 'click', byId('universe'),
      (e) ->
        u.highlight e.offsetX, e.offsetY, byId('highlight').value, byId('inherit-mark').checked
      true
    )
  onEvent 'click', byId('stop'), stop
  onEvent 'click', byId('start'), start
  onEvent 'click', byId('clear'), clear
  onEvent 'click', byId('zap'), (e) ->
    data = crosshairCursor()
    document.body.style.cursor = "url(#{data}), auto"
    onEvent( 'click', byId('universe'),
      (e) ->
        u.zap e.offsetX + 8, e.offsetY + 8
      true
    )
  for id in [ 'disease-virulence', 'disease-mortality', 'disease-cure', 'disease-health' ]
    input = byId id
    input.nextSibling.innerHTML = input.value
    onEvent 'change', input, (e) ->
      @nextSibling.innerHTML = @value
  onEvent 'click', byId('disease-wand'), (e) ->
    data = crosshairCursor 'green'
    document.body.style.cursor = "url(#{data}), auto"
    onEvent( 'click', byId('universe'),
      (e) ->
        mortalityRate = parseFloat byId('disease-mortality').value
        virulence     = parseFloat byId('disease-virulence').value
        cureRate      = parseFloat byId('disease-cure').value
        healthDivisor = parseFloat byId('disease-cure').value
        color         = byId('disease-color').value
        u.infect e.offsetX + 8, e.offsetY + 8, virulence, mortalityRate, cureRate, healthDivisor, color
      true
    )
  for e in byClass 'adder'
    do (e) ->
      type = null
      for c in e.classList
        type = c if c != 'adder'
      x = geometries[type][3]
      y = geometries[type][4]
      onEvent 'click', e, (evt) ->
        document.body.style.cursor = "url(#{e.src}), auto"
        onEvent( 'click', byId('universe'),
          (e) ->
            u.addInstance type, e.offsetX + x, e.offsetY + y
            fiddled = true unless u.running
          true
      )
)()
