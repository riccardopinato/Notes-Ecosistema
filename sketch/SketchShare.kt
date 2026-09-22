package it.notes.ecosystem.sketch

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import androidx.core.content.FileProvider
import it.notes.ecosystem.domain.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.math.*

object SketchShare {
    suspend fun png(context: Context, page: SketchPage, title: String) {
        val uri = withContext(Dispatchers.IO) {
            SketchRules.validate(page)
            val bitmap = Bitmap.createBitmap(SketchRules.WIDTH, SketchRules.HEIGHT, Bitmap.Config.ARGB_8888)
            try {
                val canvas = Canvas(bitmap)
                render(canvas, page)
                val folder = File(context.cacheDir, "sketch_exports")
                check(folder.isDirectory || folder.mkdirs())
                folder.listFiles()?.filter {
                    it.isFile && it.name.endsWith(".png") && System.currentTimeMillis() - it.lastModified() > 86400000
                }?.forEach { it.delete() }
                val file = File(folder, java.util.UUID.randomUUID().toString() + ".png")
                file.outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
                FileProvider.getUriForFile(context, context.packageName + ".sketchfiles", file)
            } finally {
                bitmap.recycle()
            }
        }
        withContext(Dispatchers.Main) {
            val send = Intent(Intent.ACTION_SEND)
                .setType("image/png")
                .putExtra(Intent.EXTRA_STREAM, uri)
                .putExtra(Intent.EXTRA_SUBJECT, title)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .apply { clipData = ClipData.newUri(context.contentResolver, title, uri) }
            context.startActivity(Intent.createChooser(send, "Condividi disegno"))
        }
    }

    suspend fun png(context: Context, document: SketchDocument, title: String) {
        png(context, document.page, title)
    }

    private fun render(canvas: Canvas, page: SketchPage) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        val guides = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0x1F607D9E
            strokeWidth = 1f
        }
        canvas.drawColor(0xFFFFFDFA.toInt())
        when (page.paper) {
            SketchPaper.PLAIN -> Unit
            SketchPaper.RULED -> {
                var y = 80f
                while (y < SketchRules.HEIGHT) {
                    canvas.drawLine(0f, y, SketchRules.WIDTH.toFloat(), y, guides)
                    y += 48f
                }
            }
            SketchPaper.GRID -> {
                var x = 40f
                while (x < SketchRules.WIDTH) {
                    canvas.drawLine(x, 0f, x, SketchRules.HEIGHT.toFloat(), guides)
                    x += 40f
                }
                var y = 40f
                while (y < SketchRules.HEIGHT) {
                    canvas.drawLine(0f, y, SketchRules.WIDTH.toFloat(), y, guides)
                    y += 40f
                }
            }
            SketchPaper.DOTS -> {
                guides.style = Paint.Style.FILL
                var x = 40f
                while (x < SketchRules.WIDTH) {
                    var y = 40f
                    while (y < SketchRules.HEIGHT) {
                        canvas.drawCircle(x, y, 1.8f, guides)
                        y += 40f
                    }
                    x += 40f
                }
            }
            SketchPaper.CORNELL -> {
                canvas.drawLine(220f, 0f, 220f, SketchRules.HEIGHT.toFloat(), guides)
                canvas.drawLine(0f, 1080f, SketchRules.WIDTH.toFloat(), 1080f, guides)
                var y = 80f
                while (y < 1080f) {
                    canvas.drawLine(220f, y, SketchRules.WIDTH.toFloat(), y, guides)
                    y += 48f
                }
            }
        }

        page.shapes.forEach { shape ->
            paint.color = shape.color
            paint.alpha = 255
            paint.strokeWidth = shape.width.toFloat()
            paint.style = Paint.Style.STROKE
            val left = min(shape.x1, shape.x2).toFloat()
            val right = max(shape.x1, shape.x2).toFloat()
            val top = min(shape.y1, shape.y2).toFloat()
            val bottom = max(shape.y1, shape.y2).toFloat()
            when (shape.kind) {
                SketchShapeKind.LINE -> canvas.drawLine(shape.x1.toFloat(), shape.y1.toFloat(), shape.x2.toFloat(), shape.y2.toFloat(), paint)
                SketchShapeKind.RECTANGLE -> canvas.drawRect(left, top, right, bottom, paint)
                SketchShapeKind.ELLIPSE -> canvas.drawOval(RectF(left, top, right, bottom), paint)
                SketchShapeKind.ARROW -> {
                    canvas.drawLine(shape.x1.toFloat(), shape.y1.toFloat(), shape.x2.toFloat(), shape.y2.toFloat(), paint)
                    val angle = atan2((shape.y2 - shape.y1).toDouble(), (shape.x2 - shape.x1).toDouble())
                    val len = 28f + shape.width * 2f
                    val a1 = angle + Math.PI * 0.82
                    val a2 = angle - Math.PI * 0.82
                    canvas.drawLine(shape.x2.toFloat(), shape.y2.toFloat(), shape.x2 + cos(a1).toFloat() * len, shape.y2 + sin(a1).toFloat() * len, paint)
                    canvas.drawLine(shape.x2.toFloat(), shape.y2.toFloat(), shape.x2 + cos(a2).toFloat() * len, shape.y2 + sin(a2).toFloat() * len, paint)
                }
            }
        }

        page.strokes.forEach { stroke ->
            paint.color = stroke.color
            paint.alpha = if (stroke.marker) 72 else 255
            val pressure = stroke.points.map { it.pressure }.average().takeIf { !it.isNaN() } ?: 1000.0
            paint.strokeWidth = stroke.width * (0.55f + 0.45f * (pressure / 1000f).toFloat())
            if (stroke.points.size == 1) {
                paint.style = Paint.Style.FILL
                canvas.drawCircle(stroke.points[0].x.toFloat(), stroke.points[0].y.toFloat(), paint.strokeWidth / 2f, paint)
            } else {
                paint.style = Paint.Style.STROKE
                val path = Path().apply {
                    moveTo(stroke.points[0].x.toFloat(), stroke.points[0].y.toFloat())
                    stroke.points.drop(1).forEach { lineTo(it.x.toFloat(), it.y.toFloat()) }
                }
                canvas.drawPath(path, paint)
            }
        }

        page.texts.forEach { item ->
            paint.color = item.color
            paint.alpha = 255
            paint.style = Paint.Style.FILL
            paint.textSize = item.size.toFloat()
            item.text.lineSequence().take(12).forEachIndexed { index, line ->
                canvas.drawText(line.take(120), item.x.toFloat(), item.y + index * item.size * 1.25f, paint)
            }
        }
    }
}
