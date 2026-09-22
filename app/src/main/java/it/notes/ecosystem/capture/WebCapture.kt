package it.notes.ecosystem.capture

import android.text.Html
import it.notes.ecosystem.domain.SmartCaptureRules
import it.notes.ecosystem.domain.WebSnapshot
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.URI
import java.net.URL
import java.nio.charset.Charset
import java.util.Locale
import java.util.zip.GZIPInputStream

class WebCapture {

    suspend fun fetch(rawUrl: String): WebSnapshot = withContext(Dispatchers.IO) {
        var current = SmartCaptureRules.normalizeHttpUrl(rawUrl)
        val requested = current

        repeat(6) { redirectIndex ->
            validatePublicDestination(current)

            val connection = URL(current).openConnection() as HttpURLConnection
            try {
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 8_000
                connection.readTimeout = 10_000
                connection.requestMethod = "GET"
                connection.setRequestProperty(
                    "User-Agent",
                    "NotesEcosystem/0.22 Android SmartCapture"
                )
                connection.setRequestProperty(
                    "Accept",
                    "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1"
                )
                connection.setRequestProperty("Accept-Encoding", "gzip")

                val code = connection.responseCode

                if (code in 300..399) {
                    require(redirectIndex < 5) { "Troppi reindirizzamenti." }
                    val location = connection.getHeaderField("Location")
                        ?: error("Reindirizzamento web non valido.")
                    current = URI(current).resolve(location).toString()
                    current = SmartCaptureRules.normalizeHttpUrl(current)
                    return@repeat
                }

                require(code in 200..299) {
                    "La pagina ha risposto con codice HTTP $code."
                }

                val contentType = connection.contentType.orEmpty().lowercase(Locale.ROOT)
                require(
                    contentType.contains("text/html") ||
                        contentType.contains("application/xhtml+xml")
                ) {
                    "Il link non contiene una pagina HTML."
                }

                val charset = charsetFromContentType(connection.contentType)
                val raw = if (
                    connection.contentEncoding.equals("gzip", ignoreCase = true)
                ) {
                    GZIPInputStream(connection.inputStream)
                } else {
                    connection.inputStream
                }

                val bytes = raw.use {
                    readLimitedWeb(it, SmartCaptureRules.MAX_WEB_HTML_BYTES)
                }

                val html = bytes.toString(charset)
                return@withContext parseSnapshot(requested, current, html)
            } finally {
                connection.disconnect()
            }
        }

        error("Impossibile completare l'acquisizione web.")
    }

    internal fun parseSnapshot(
        requestedUrl: String,
        finalUrl: String,
        html: String,
    ): WebSnapshot {
        val withoutScripts = html
            .replace(
                Regex("""(?is)<script\b[^>]*>.*?</script>"""),
                " "
            )
            .replace(
                Regex("""(?is)<style\b[^>]*>.*?</style>"""),
                " "
            )
            .replace(
                Regex("""(?is)<noscript\b[^>]*>.*?</noscript>"""),
                " "
            )
            .replace(
                Regex("""(?is)<svg\b[^>]*>.*?</svg>"""),
                " "
            )

        val title = (firstGroup(
            withoutScripts,
            Regex("""(?is)<title\b[^>]*>(.*?)</title>"""),
        ) ?: "").let(::htmlToPlain)
            .ifBlank {
                URI(finalUrl).host ?: finalUrl
            }
            .take(300)

        val description =
            metaContent(withoutScripts, "description")
                ?: metaProperty(withoutScripts, "og:description")
                ?: ""

        val canonicalRaw = firstGroup(
            withoutScripts,
            Regex(
                """(?is)<link\b(?=[^>]*\brel\s*=\s*["']?canonical["']?)[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>"""
            ),
        )

        val canonical = runCatching {
            if (canonicalRaw.isNullOrBlank()) finalUrl
            else SmartCaptureRules.normalizeHttpUrl(
                URI(finalUrl).resolve(canonicalRaw).toString()
            )
        }.getOrDefault(finalUrl)

        val articleHtml =
            firstGroup(
                withoutScripts,
                Regex("""(?is)<article\b[^>]*>(.*?)</article>"""),
            )
                ?: firstGroup(
                    withoutScripts,
                    Regex("""(?is)<main\b[^>]*>(.*?)</main>"""),
                )
                ?: firstGroup(
                    withoutScripts,
                    Regex("""(?is)<body\b[^>]*>(.*?)</body>"""),
                )
                ?: withoutScripts

        val text = SmartCaptureRules.clipWebText(
            htmlToPlain(
                articleHtml
                    .replace(Regex("""(?is)</(p|div|section|article|li|h[1-6]|blockquote)>"""), "$0\n")
                    .replace(Regex("""(?is)<br\s*/?>"""), "\n")
            )
        )

        return WebSnapshot(
            requestedUrl = requestedUrl,
            finalUrl = canonical,
            title = title,
            description = htmlToPlain(description).take(1_000),
            text = text,
        )
    }

    private fun validatePublicDestination(url: String) {
        val uri = URI(url)
        val host = requireNotNull(uri.host) { "Host non valido." }

        require(
            host.lowercase(Locale.ROOT) !in setOf(
                "localhost",
                "localhost.localdomain",
                "0.0.0.0",
            )
        ) {
            "Indirizzi locali non supportati."
        }

        val addresses = InetAddress.getAllByName(host)
        require(addresses.isNotEmpty()) { "Host non raggiungibile." }

        require(addresses.none { address ->
            address.isAnyLocalAddress ||
                address.isLoopbackAddress ||
                address.isLinkLocalAddress ||
                address.isSiteLocalAddress ||
                address.isMulticastAddress
        }) {
            "Per sicurezza non vengono acquisiti indirizzi di rete locale."
        }
    }

    private fun charsetFromContentType(type: String?): Charset {
        val charsetName = type
            ?.split(';')
            ?.map { it.trim() }
            ?.firstOrNull { it.startsWith("charset=", ignoreCase = true) }
            ?.substringAfter('=')
            ?.trim()
            ?.trim('"', '\'')
        return runCatching {
            charsetName?.let(Charset::forName)
        }.getOrNull() ?: Charsets.UTF_8
    }

    private fun metaContent(html: String, name: String): String? {
        val escaped = Regex.escape(name)
        return firstGroup(
            html,
            Regex(
                """(?is)<meta\b(?=[^>]*\bname\s*=\s*["']?$escaped["']?)[^>]*\bcontent\s*=\s*["']([^"']*)["'][^>]*>"""
            ),
        )
    }

    private fun metaProperty(html: String, property: String): String? {
        val escaped = Regex.escape(property)
        return firstGroup(
            html,
            Regex(
                """(?is)<meta\b(?=[^>]*\bproperty\s*=\s*["']?$escaped["']?)[^>]*\bcontent\s*=\s*["']([^"']*)["'][^>]*>"""
            ),
        )
    }

    private fun firstGroup(input: String, regex: Regex): String? =
        regex.find(input)?.groupValues?.getOrNull(1)

    private fun htmlToPlain(value: String): String =
        Html.fromHtml(value, Html.FROM_HTML_MODE_LEGACY)
            .toString()
            .replace('\u00A0', ' ')
            .replace(Regex("""[ \t]{2,}"""), " ")
            .replace(Regex("""\n[ \t]+"""), "\n")
            .replace(Regex("""\n{3,}"""), "\n\n")
            .trim()
}

private fun readLimitedWeb(
    input: java.io.InputStream,
    limit: Int,
): ByteArray {
    val output = ByteArrayOutputStream()
    val buffer = ByteArray(16 * 1024)

    while (true) {
        val read = input.read(buffer)
        if (read < 0) break
        require(output.size() + read <= limit) {
            "Pagina web troppo grande per l'acquisizione rapida."
        }
        output.write(buffer, 0, read)
    }

    return output.toByteArray()
}
