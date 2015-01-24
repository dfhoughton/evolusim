initializationParameters =
  pause: [ 10, 0, 1000, 'minimum pause between ticks' ]
  maxDistance: [ 60, 30, 100, 'maximum distance an organism can see' ]
  initialCreatures:
    stones:
      num: [ 40, 0, 100 ]
    plants:
      num: [ 100, 10, 500 ]
      init:
        bodyColor: '#00ff00'
        radius: [ 4, 2, 20, 'plant size' ]
    herbivores:
      num: [ 8, 0, 100 ]
      init:
        bodyColor: '#701614'
        radius: [ 5, 2, 20, 'body size' ]
    carnivores:
      num: [ 40, 0, 100 ]
      init:
        bodyColor: '#ff0000'
        radius: [ 6, 2, 20, 'body size' ]
byId = (id) -> document.getElementById(id)
decamelize = (str) ->
  str = str.replace /([a-z])([A-Z])/g, "$1 $2"
  str.toLowerCase()
text = (t) ->
  document.createTextNode(t)
intFormat = (int) ->
  ar = ( '' + int ).split('').reverse()
  ar2 = []
  for v, i in ar
    ar2.push ',' if i && !( i % 3 )
    ar2.push v
  ar2.reverse().join ''
create = (tag, cz) ->
  e = document.createElement(tag)
  e.setAttribute( 'class', cz ) if cz
  e
chartType = 'all'
( ->
  tabs = []
  div = byId 'tab-div'
  while div = div.nextSibling
    tabs.push div if div.nodeType == 1
  child = byId('tabs').firstChild
  sibs = []
  while child = child.nextSibling
    if child.nodeType == 1 && child.className != 'buffer'
      sibs.push child
      child.onclick = ( (c) ->
          ->
            return if c.className == 'active'
            s.removeAttribute 'class' for s in sibs
            c.setAttribute 'class', 'active'
            t.style.display = 'none' for t in tabs
            chartType = c.innerHTML
            byId( chartType + '-chart' ).style.display = 'block'
            showCharts(chartType)
        )(child)
)()
[ u, makeCharts, loaded, paramsDefined ] = [ null, false, false, false ]
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
  s.onchange = ->
    object[label] = s.value
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
window.params = (element) ->
  unless paramsDefined
    makeInputs()
    paramsDefined = true
  paramDiv = byId 'options'
  if element.innerHTML == 'show params'
    element.innerHTML = 'hide params'
    paramDiv.style.display = 'inline-table'
  else
    element.innerHTML = 'show params'
    paramDiv.style.display = 'none'
window.toggleCharts = (element) ->
  try
    makeCharts = !makeCharts
    txt = if makeCharts then 'charts off' else 'charts on'
    element.innerHTML = txt
    unless loaded
      google.load 'visualization', '1', packages: ['corechart']
      google.setOnLoadCallback drawChart
      loaded = true
  catch e
    alert "Could not make charts: #{e}"
    makeCharts = false
    loaded = false
  byId('charts-div').style.display = 'block' if loaded
makeUniverse = ->
  p = convertParams()
  p.callback = collectData
  u = new Universe 'universe', p
evoData =
  resetNum: 1
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
        colors: [ 'green', 'brown', 'red' ]
        rows: []
      Energy:
        id: 'energy'
        htitle: 'Time (ticks)'
        vtitle: 'Net energy embodied by indviduals'
        collector: (stats, rows) ->
          counts = Plant: 0, Herbivore: 0, Carnivore: 0
          counts[description.type] += description.hp for description in stats
          row = [ evoData.generation, counts.Plant, counts.Herbivore, counts.Carnivore ]
          rows.push row
        names: [ 'Plant', 'Herbivore', 'Carnivore' ]
        colors: [ 'green', 'brown', 'red' ]
        rows: []
collectData = ->
  evoData.generation += 1
  byId('ticks').innerHTML = intFormat evoData.generation
  byId('created').innerHTML = intFormat u.thingsCreated()
  byId('current').innerHTML = intFormat u.currentThings()
  byId('plant-count').innerHTML = intFormat u.plantCount()
  byId('animal-count').innerHTML = intFormat u.animalCount()
  byId('herbivore-count').innerHTML = intFormat u.herbivoreCount()
  byId('carnivore-count').innerHTML = intFormat u.carnivoreCount()
  stats = u.describe()
  for tab, specs of evoData.charts
    for title, details of specs
      details.collector stats, details.rows
  drawChart() if makeCharts
window.start = ->
  if u
    u.stop()
    evoData.generation = 0
    clearCharts()
    u.erase()
  makeUniverse()
  u.run()
  byId('stop').innerHTML = 'stop'
window.stop = (element) ->
  return unless u
  if u.running
    u.stop()
    element.innerHTML = 'resume'
  else
    u.run()
    element.innerHTML = 'stop'
trimData = (data) ->
  return data if data.length < 500
  results = []
  results.push data[i] for i in [data.length - 500...data.length]
  results
clearCharts = ->
  resetNum = evoData.resetNum++
  for type, subtype of evoData.charts
    for title, specs of subtype
      id = specs.id
      if chart = specs.chart
        chart.clearChart()
        specs.chart = null
        specs.rows = []
      e = byId id
      id.replace /\d+$/, ''
      id = specs.id = "#{id}#{resetNum}"
      div = create 'div', 'chart'
      div.id = id
      e.parentNode.replaceChild div, e
drawChart = ->
  for title, specs of evoData.charts[chartType]
    id     = specs.id
    rows   = trimData specs.rows
    names  = specs.names
    chart  = specs.chart
    htitle = specs.htitle
    vtitle = specs.vtitle
    width  = specs.width || 1000
    height = specs.height || 400
    colors = specs.colors
    data = new google.visualization.DataTable()
    data.addColumn 'number', 'X'
    data.addColumn 'number', n for n in names
    data.addRows rows
    options =
      title: title
      width: width
      height: height
      hAxis:
        title: htitle
      vAxis:
        title: vtitle
    options.colors = colors if colors
    if chart
      chart.clearChart()
    else
      specs.chart = chart = new google.visualization.LineChart byId(id)
    chart.draw data, options