class window.PDFTextMapper

  CONTEXT_LEN = 32

  # Are we working with a PDF document?
  @applicable: -> PDFView?.initialized ? false

  @requiresVirtualAnchoring: true
        
  constructor: ->
    @setEvents()     

  _onPageRendered: (evt) =>
    # A new page was rendered
    pageIndex = evt.detail.pageNumber - 1
    #console.log "Allegedly rendered page #" + pageIndex

    # Is it really rendered?
    unless @isPageRendered pageIndex
    #console.log "Page #" + pageIndex + " is not really rendered yet."
      setTimeout (=> @_onPageRendered evt), 1000
      return

    # Collect info about the new DOM subtree
    @_mapPage @pageInfo[pageIndex]

    # Announce the newly available page
    @onPageReady pageIndex

  # Override point: this is called when a new page has become fully available
  onPageReady: (index) ->
    console.log "Page #" + index + " is ready!"

  setEvents: ->
    addEventListener "pagerender", @_onPageRendered

  _extractionPattern: /[ ]/g
  _parseExtractedText: (text) => text.replace @_extractionPattern, ""

  _selectionPattern: /[ ]/g
  _parseSelectedText: (text) => text.replace @_selectionPattern, ""

  # Extract the text from the PDF, and store the char offset <--> page mapping
  scan: ->
    console.log "Scanning PDF for text..."

    pendingScan = new PDFJS.Promise()

    # Tell the Find Controller to go digging
    PDFFindController.extractText()

    # When all the text has been extracted
    PDFJS.Promise.all(PDFFindController.extractTextPromises).then =>
      # PDF.js text extraction has finished.

      # Post-process the extracted text
      @pageInfo = ({ content: @_parseExtractedText page } for page in PDFFindController.pageContents)

      # Join all the text together
      @corpus = (info.content for info in @pageInfo).join " "

      # Go over the pages, and calculate some basic info
      pos = 0
      @pageInfo.forEach (info, i) =>
        info.index = i
        info.len = info.content.length        
        info.start = pos
        info.end = (pos += info.len + 1)

      # OK, we are ready to rock.
      pendingScan.resolve()

      # Go over the pages again, and map the rendered ones
      @pageInfo.forEach (info, i) =>
        if @isPageRendered i
          @_mapPage info
          setTimeout => @onPageReady i

    # Return the promise
    pendingScan

  # Get the page index for a given character position
  getPageIndexForPos: (pos) ->
    for info in @pageInfo
      if info.start <= pos < info.end
        return info.index
        console.log "Not on page " + info.index
    return -1

  # Determine whether a given page has been rendered
  isPageRendered: (index) ->
    return PDFView.pages[index]?.textLayer?.renderingDone

  # Create the mappings for a given page    
  _mapPage: (info) ->
#    console.log "Mapping page #" + info.index + "..."
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
    #console.log "These are on pages [" + startIndex + "; " + endIndex + "]."

    # Are these all rendered?
    for index in [startIndex..endIndex]
      unless @isPageRendered index # If this is not rendered
        console.log "Can not calculate mappings, because page #" + index + " is not rendered yet."
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
