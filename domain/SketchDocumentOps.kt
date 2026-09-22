package it.notes.ecosystem.domain

object SketchDocumentOps {
    fun replaceActive(document: SketchDocument, page: SketchPage): SketchDocument {
        val pages = document.pages.toMutableList()
        pages[document.activePage] = SketchRules.validate(page)
        return SketchRules.validate(document.copy(pages = pages))
    }

    fun addPage(document: SketchDocument, paper: SketchPaper = document.page.paper): SketchDocument {
        require(document.pages.size < SketchRules.MAX_PAGES) { "Massimo ${SketchRules.MAX_PAGES} pagine." }
        val pages = document.pages + SketchPage(paper = paper)
        return SketchRules.validate(document.copy(pages = pages, activePage = pages.lastIndex))
    }

    fun duplicatePage(document: SketchDocument): SketchDocument {
        require(document.pages.size < SketchRules.MAX_PAGES) { "Massimo ${SketchRules.MAX_PAGES} pagine." }
        val source = document.page
        val copy = source.copy(
            id = java.util.UUID.randomUUID().toString(),
            strokes = source.strokes.map { it.copy(id = java.util.UUID.randomUUID().toString()) },
            shapes = source.shapes.map { it.copy(id = java.util.UUID.randomUUID().toString()) },
            texts = source.texts.map { it.copy(id = java.util.UUID.randomUUID().toString()) },
        )
        val pages = document.pages.toMutableList().apply { add(document.activePage + 1, copy) }
        return SketchRules.validate(document.copy(pages = pages, activePage = document.activePage + 1))
    }

    fun deleteActivePage(document: SketchDocument): SketchDocument {
        if (document.pages.size == 1) return SketchDocument(listOf(SketchPage(paper = document.page.paper)), 0)
        val pages = document.pages.toMutableList().apply { removeAt(document.activePage) }
        val next = document.activePage.coerceAtMost(pages.lastIndex)
        return SketchRules.validate(document.copy(pages = pages, activePage = next))
    }

    fun setActive(document: SketchDocument, index: Int): SketchDocument {
        require(index in document.pages.indices)
        return document.copy(activePage = index)
    }

    fun setPaper(document: SketchDocument, paper: SketchPaper): SketchDocument =
        replaceActive(document, document.page.copy(paper = paper))
}
