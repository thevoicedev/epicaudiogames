package com.epicaudiogames.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.epicaudiogames.app.R

// The Mini Games look: Lilita One, a light blue backdrop, a slate blue header bar, white outlined titles.

val Lilita = FontFamily(Font(R.font.lilita_one))

object Palette {
    val headerTop = Color(0xFF4E6383)
    val headerBottom = Color(0xFF5E86AF)
    val headerLine = Color(0xFFDDE8F3)
    val backdropCenter = Color(0xFF90D3E9)
    val backdropEdge = Color(0xFF3E7FC3)
    val ink = Color(0xFF1F3B5C)
    val title = Color(0xFF2F72B9)
    val yes = Color(0xFF28A745)
    val no = Color(0xFFDC3545)
    val choice = Color(0xFF007BFF)
    val gold = Color(0xFFFFC107)
    val listen = Color(0xFF3DDC84)
    val card = Color(0xFFFFFFFF)
    val reply = Color(0xFFFFF3C4)
}

/** Speaker name colours, picked by name so each character keeps theirs. */
private val SPEAKERS = listOf(
    Color(0xFF2F72B9), Color(0xFFD9480F), Color(0xFF2B8A3E), Color(0xFF862E9C), Color(0xFFC2255C),
    Color(0xFF1098AD), Color(0xFFE67700), Color(0xFF5F3DC4),
)

fun speakerColor(who: String): Color =
    if (who == "NARRATOR") Palette.ink else SPEAKERS[Math.floorMod(who.hashCode(), SPEAKERS.size)]

@Composable
fun EpicTheme(content: @Composable () -> Unit) {
    val base = TextStyle(fontFamily = Lilita, color = Palette.ink)
    MaterialTheme(
        colorScheme = lightColorScheme(primary = Palette.choice, secondary = Palette.gold, background = Palette.backdropEdge),
        typography = Typography(
            displayLarge = base.copy(fontSize = 40.sp),
            headlineMedium = base.copy(fontSize = 28.sp),
            titleLarge = base.copy(fontSize = 22.sp),
            titleMedium = base.copy(fontSize = 18.sp),
            bodyLarge = base.copy(fontSize = 17.sp, lineHeight = 23.sp),
            bodyMedium = base.copy(fontSize = 15.sp, lineHeight = 20.sp),
            labelLarge = base.copy(fontSize = 17.sp),
            labelMedium = base.copy(fontSize = 13.sp),
        ),
        content = content,
    )
}

/** The light blue backdrop, brightest at the top middle. */
@Composable
fun Backdrop(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    Box(
        modifier.drawBehind {
            drawRect(
                Brush.radialGradient(
                    listOf(Palette.backdropCenter, Palette.backdropEdge),
                    center = Offset(size.width / 2, size.height * 0.25f),
                    radius = size.maxDimension * 0.75f,
                ),
            )
        },
        content = content,
    )
}

/** Text drawn twice: a dark outline, then the fill (the Mini Games titles). */
@Composable
fun OutlinedText(
    text: String,
    modifier: Modifier = Modifier,
    size: TextUnit = 22.sp,
    fill: Color = Color.White,
    outline: Color = Palette.ink,
    maxLines: Int = 1,
) {
    val style = TextStyle(fontFamily = Lilita, fontSize = size)
    Box(modifier) {
        Text(text, style = style.copy(color = outline, drawStyle = Stroke(width = size.value / 4)), maxLines = maxLines,
            overflow = TextOverflow.Ellipsis)
        Text(text, style = style.copy(color = fill), maxLines = maxLines, overflow = TextOverflow.Ellipsis)
    }
}

/** The header bar, under the status bar. */
@Composable
fun HeaderBar(title: String, onBack: (() -> Unit)? = null, actions: @Composable RowScope.() -> Unit = {}) {
    Box(
        Modifier
            .fillMaxWidth()
            .background(Brush.verticalGradient(listOf(Palette.headerTop, Palette.headerBottom)))
            .windowInsetsPadding(WindowInsets.statusBars),
    ) {
        Row(
            Modifier.fillMaxWidth().height(60.dp).padding(horizontal = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (onBack != null) {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Color.White)
                }
            } else {
                Spacer(Modifier.width(10.dp))
            }
            OutlinedText(title, Modifier.weight(1f), size = 24.sp)
            actions()
        }
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(2.dp).background(Palette.headerLine))
    }
}

@Composable
fun Dot(color: Color, modifier: Modifier = Modifier) =
    Box(modifier.size(10.dp).background(color, shape = androidx.compose.foundation.shape.CircleShape))
