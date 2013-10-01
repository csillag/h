class window.PDFTextMapper

  CONTEXT_LEN = 32
        
  constructor: ->
    @setEvents()     

  setEvents: ->
    addEventListener("pagerender", (evt) =>
      # A new page was rendered
      pageIndex = evt.detail.pageNumber - 1
      console.log "rendered page #" + pageIndex

      # Collect info about the new DOM subtree
      @_mapPage @pageInfo[pageIndex]

      # TODO: do something about annotations pending for this page
    )

  _extractionPattern: /[ ]/g
  _parseExtractedText: (text) => text.replace @_extractionPattern, ""

  _selectionPattern: /[ ]/g
  _parseSelectedText: (text) => text.replace @_selectionPattern, ""

  # Extract the text from the PDF, and store the char offset <--> page mapping
  scan: ->
    console.log "Scanning PDF for text..."

    # Tell the Find Controller to go digging
    PDFFindController.extractText()

    # When all the text has been extracted
    PDFJS.Promise.all(PDFFindController.extractTextPromises).then =>
      console.log "Text extraction has finished."
      @pageInfo = ({ content: @_parseExtractedText page } for page in PDFFindController.pageContents)
      @corpus = (info.content for info in @pageInfo).join " "
      pos = 0
      @pageInfo.forEach (info, i) =>
        info.index = i
        info.len = info.content.length        
        info.start = pos
        info.end = (pos += info.len + 1)
        if @isPageRendered i then @_mapPage info
      console.log "Mappings calculated."

    null

  # Get the page index for a given character position
  getPageIndexForPos: (pos) ->
    for info in @pageInfo
      if info.start <= pos < info.end
        return info.index
        console.log "Not on page " + info.index
    return -1

  # Determine whether a given page has been rendered
  isPageRendered: (index) ->
    return PDFView.pages[index]?.textLayer?

  # Create the mappings for a given page    
  _mapPage: (info) ->
    console.log "Mapping page #" + info.index        
    info.domMapper = new DomTextMapper()
    if @_parseSelectedText?
      info.domMapper.postProcess = @_parseSelectedText
    info.domMatcher = new DomTextMatcher info.domMapper
    info.node = PDFView.pages[info.index].textLayer.textLayerDiv
    info.domMapper.setRootNode info.node
    info.domMatcher.scan()
    renderedContent = info.domMapper.path["."].content
    if renderedContent isnt info.content
      console.log "Oops. Mismatch between rendered and extracted text!"
      console.log "Extracted version: " + info.content
      console.log "Rendered version: " + info.renderedContent

  # Look up the page for a given DOM node
  getPageForNode: (node) ->
    # Search for the root of this page
    div = node
    while (
      (div.nodeType isnt Node.ELEMENT_NODE) or
      not div.getAttribute("class")? or
      (div.getAttribute("class") isnt "textLayer")
    )
      div = div.parentNode

    # Fetch the page number from the id. ("pageContainerN")
    index = parseInt div.parentNode.id.substr(13) - 1

    # Look up the page
    @pageInfo[index]

  # Look up info about a given DOM node
  getDataForNode: (node) ->
    pageData = @getPageForNode node
    nodeData = pageData.domMapper.getInfoForNode node
    info =
      page: pageData
      node: nodeData

  # Look up info about a give DOM node, uniting page and node info
  getInfoForNode: (node) ->
    data = @getDataForNode node
    # Copy info about the node
    info = {}
    for k,v of data.node
      info[k] = v
    # Correct the chatacter offsets with that of the page
    info.start += data.page.start
    info.end += data.page.start
    info

  # Return some data about a given character range
  getMappingsForCharRange: (start, end) ->
    #console.log "Get mappings for char range [" + start + "; " + end + "]."

    # Check out which pages are these on
    startIndex = @getPageIndexForPos start
    endIndex = @getPageIndexForPos end

    # Are these all rendered?
    for index in [startIndex..endIndex]
      unless @isPageRendered index # If this is not rendered
        return rendered: false     # give up

    # TODO: I saw a cross-page test fail once. Why?

    # Is this a cross-page range?
    unless startIndex is endIndex
      # TODO: support cross-page mappings
      console.log "Warning: cross-page ranges are not yet supported!"
      console.log "(Involves pages: " + ([startIndex..endIndex]) + ")"
      return null

    # Calculate in-page offsets
    startInfo = @pageInfo[startIndex]
    realStart = start - startInfo.start
    realEnd = end - startInfo.start

    # Get the range inside the page
    mappings = startInfo.domMapper.getMappingsForCharRange realStart, realEnd

    # Add the rendered flag to the mappings info
    mappings.rendered = true

    # Return the resulting data structure
    mappings

  getContentForCharRange: (start, end) ->
    text = @corpus.substr start, end - start
    text.trim()

  getContextForCharRange: (start, end) ->
    prefixStart = Math.max 0, start - CONTEXT_LEN
    prefixLen = start - prefixStart
    prefix = @corpus.substr prefixStart, prefixLen
    suffix = @corpus.substr end, prefixLen
    [prefix.trim(), suffix.trim()]
