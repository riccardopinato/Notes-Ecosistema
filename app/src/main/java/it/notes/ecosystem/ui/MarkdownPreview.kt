package it.notes.ecosystem.ui

import android.content.Intent
import android.net.Uri
import android.text.Spanned
import android.widget.TextView
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import io.noties.markwon.AbstractMarkwonPlugin
import io.noties.markwon.Markwon
import io.noties.markwon.MarkwonConfiguration
import io.noties.markwon.ext.tasklist.TaskListPlugin
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private data class RenderedMarkdown(val source: String, val renderer: Markwon, val content: Spanned)

@Composable
fun MarkdownPreview(body: String, modifier: Modifier = Modifier, onOpenNote: (String)->Unit = {}, onOpenAttachment:(String)->Unit={}) {
    val context = LocalContext.current
    val openNote by rememberUpdatedState(onOpenNote)
    val openAttachment by rememberUpdatedState(onOpenAttachment)
    val ink = MaterialTheme.colorScheme.onSurface.toArgb()
    val accent = MaterialTheme.colorScheme.primary.toArgb()
    val paper = MaterialTheme.colorScheme.surface.toArgb()
    var failed by remember(body) { mutableStateOf(false) }
    val rendered by produceState<RenderedMarkdown?>(null, body, ink, accent, paper) {
        value = null
        if (body.length <= 200_000) try { value = withContext(Dispatchers.Default) {
            // A new parser per render avoids sharing mutable parser state across cancelled jobs.
            val renderer = Markwon.builder(context)
                .usePlugin(TaskListPlugin.create(accent, ink, paper))
                .usePlugin(object : AbstractMarkwonPlugin() {
                    override fun configureConfiguration(builder: MarkwonConfiguration.Builder) {
                        builder.linkResolver { view, link ->
                            val asset=it.notes.ecosystem.domain.Attachments.target(link)
                            if(asset!=null){openAttachment(asset);return@linkResolver}
                            val internal = it.notes.ecosystem.domain.Knowledge.targetId(link)
                            if(internal!=null) { openNote(internal); return@linkResolver }
                            val uri = Uri.parse(link)
                            if (uri.scheme?.lowercase() in listOf("https", "http") && !uri.host.isNullOrBlank()) {
                                runCatching { view.context.startActivity(Intent(Intent.ACTION_VIEW, uri)) }
                            }
                        }
                    }
                }).build()
            RenderedMarkdown(body, renderer, renderer.toMarkdown(body))
        } } catch (e: CancellationException) { throw e }
        catch (_: Exception) { failed = true }
    }
    Column(modifier) {
        if (body.length > 200_000) Text("Questa nota è troppo lunga per l’anteprima. Il testo completo resta disponibile in Scrivi.")
        else if (failed) Text("Anteprima non disponibile. Il testo completo resta in Scrivi.")
        else if (rendered == null || rendered?.source != body) LinearProgressIndicator(Modifier.fillMaxWidth())
        else {
            Text("Anteprima di lettura · modifica le spunte in Checklist. Le immagini esterne non vengono caricate.", style = MaterialTheme.typography.labelSmall)
            val result = rendered!!
            AndroidView(factory = { TextView(it).apply { textSize = 18f; setLineSpacing(0f, 1.2f) } },
                modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()), update = { view ->
                    view.setTextColor(ink); view.setLinkTextColor(accent)
                    if (view.tag !== result) { result.renderer.setParsedMarkdown(view, result.content); view.tag = result }
                })
        }
    }
}
