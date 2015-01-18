initializationParameters =
  pause: [ 10, 0, 1000, 'minimum pause between ticks' ]
  maxDistance: [ 60, 30, 100, 'maximum distance an organism can see' ]
  initialCreatures:
    stones:
      num: [ 40, 0, 100 ]
    plants:
      num: [ 100, 10, 500 ]
    herbivores:
      num: [ 8, 0, 100 ]
    carnivores:
      num: [ 40, 0, 100 ]
byId = (id) -> document.getElementById(id)
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
    else
      copy[k] = convertParams v
  copy
makeSliders = (obj=initializationParameters, parent=byId('options')) ->
  for k,v of obj
    div = create 'div', 'indenter'
    h = create 'div', 'param-header'
    h.innerHTML = k
    div.appendChild h
    parent.appendChild div
    if v instanceof Array
      makeSlider k, obj, div
    else
      makeSliders v, div
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
    makeSliders()
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
    text = if makeCharts then 'charts off' else 'charts on'
    element.innerHTML = text
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
        rows: []
collectData = ->
  evoData.generation += 1
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
      id = specs.id = "id#{resetNum}"
      div = create 'div', 'chart'
      div.id = id
      e.parentNode.replaceChild div, e
drawChart = ->
  data = new google.visualization.DataTable()
  for title, specs of evoData.charts[chartType]
    id     = specs.id
    rows   = trimData specs.rows
    names  = specs.names
    chart  = specs.chart
    htitle = specs.htitle
    vtitle = specs.vtitle
    width  = specs.width || 1000
    height = specs.height || 400
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
    if chart
      chart.clearChart()
    else
      specs.chart = chart = new google.visualization.LineChart byId(id)
    chart.draw data, options
