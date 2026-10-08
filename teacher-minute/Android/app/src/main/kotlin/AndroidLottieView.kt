package teacher.minute

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import com.airbnb.lottie.compose.LottieAnimation
import com.airbnb.lottie.compose.LottieCompositionSpec
import com.airbnb.lottie.compose.LottieConstants
import com.airbnb.lottie.compose.rememberLottieComposition
import skip.ui.ComposeContext
import skip.ui.ComposeView

/**
 * A Lottie animation, looping, for `LottieLoopView`. The Swift side reads the
 * JSON from its module's resources and hands it over, so both platforms draw
 * the one file.
 */
object AndroidLottieView {
    @JvmStatic
    fun create(json: String): ComposeView {
        return ComposeView { context: ComposeContext ->
            LoopingAnimation(json = json, modifier = context.modifier)
        }
    }

    @Composable
    private fun LoopingAnimation(json: String, modifier: Modifier) {
        val composition by rememberLottieComposition(LottieCompositionSpec.JsonString(json))
        LottieAnimation(
            composition = composition,
            iterations = LottieConstants.IterateForever,
            modifier = modifier.fillMaxSize()
        )
    }
}
