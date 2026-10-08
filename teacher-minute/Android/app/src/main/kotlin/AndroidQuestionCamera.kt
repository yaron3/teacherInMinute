package teacher.minute

import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.util.Base64
import android.util.Size
import android.util.Log
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import skip.ui.ComposeContext
import skip.ui.ComposeView
import java.io.ByteArrayOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * The back camera behind the student's home (`QuestionCameraPreview` in Swift):
 * a live preview, and a still of the question when the student takes one.
 *
 * The camera belongs to the preview. It is bound while the preview is composed
 * and released when it leaves — the text tab, a lesson, another section — so it
 * is never held under a video lesson that needs it. Bound to the activity's
 * lifecycle, it also stops by itself while the app is in the background.
 */
object AndroidQuestionCamera {
    private const val TAG = "QuestionCamera"
    /**
     * The longer side of an uploaded photo, as on iOS: enough to read a page
     * of sums across a phone's screen, and a fraction of a full frame to
     * capture, encode and upload.
     */
    private const val MAX_DIMENSION = 1600
    private const val JPEG_QUALITY = 85
    private const val CAPTURE_TIMEOUT_SECONDS = 20L

    private val captureExecutor = Executors.newSingleThreadExecutor()
    /** The still-photo use case of the preview on screen, if there is one. */
    private val currentCapture = AtomicReference<ImageCapture?>(null)

    @JvmStatic
    fun isAvailable(): Boolean {
        val activity = MainActivity.currentActivity ?: return false
        return activity.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
    }

    @JvmStatic
    fun create(): ComposeView {
        return ComposeView { context: ComposeContext ->
            CameraPreview(modifier = context.modifier)
        }
    }

    /**
     * Renders onto a `TextureView` (COMPATIBLE) rather than a `SurfaceView`:
     * the home draws its controls and a fade over the preview, and a
     * `SurfaceView` sits in its own layer outside the window.
     */
    @Composable
    private fun CameraPreview(modifier: Modifier) {
        val androidContext = LocalContext.current
        val previewView = remember {
            PreviewView(androidContext).apply {
                implementationMode = PreviewView.ImplementationMode.COMPATIBLE
                scaleType = PreviewView.ScaleType.FILL_CENTER
            }
        }

        DisposableEffect(previewView) {
            val owner = (androidContext as? LifecycleOwner) ?: MainActivity.currentActivity
            val preview = Preview.Builder().build()
            val capture = ImageCapture.Builder()
                .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                // A frame near the size it is uploaded at, rather than the
                // sensor's full 12MP or more that `encode` would only shrink.
                // Sizes are in the sensor's landscape orientation.
                .setResolutionSelector(
                    ResolutionSelector.Builder()
                        .setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY)
                        .setResolutionStrategy(
                            ResolutionStrategy(
                                Size(MAX_DIMENSION, MAX_DIMENSION * 3 / 4),
                                ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
                            )
                        )
                        .build()
                )
                .build()
            val providerFuture = ProcessCameraProvider.getInstance(androidContext)
            var isDisposed = false

            providerFuture.addListener({
                // The provider can arrive after the preview has already left.
                if (isDisposed || owner == null) return@addListener
                try {
                    val provider = providerFuture.get()
                    preview.setSurfaceProvider(previewView.surfaceProvider)
                    provider.bindToLifecycle(owner, CameraSelector.DEFAULT_BACK_CAMERA, preview, capture)
                    currentCapture.set(capture)
                    Log.i(TAG, "camera bound")
                } catch (error: Exception) {
                    Log.e(TAG, "Could not start the camera", error)
                }
            }, ContextCompat.getMainExecutor(androidContext))

            onDispose {
                isDisposed = true
                currentCapture.compareAndSet(capture, null)
                if (providerFuture.isDone) {
                    try {
                        providerFuture.get().unbind(preview, capture)
                        Log.i(TAG, "camera released")
                    } catch (error: Exception) {
                        Log.w(TAG, "Could not release the camera", error)
                    }
                }
            }
        }

        AndroidView(factory = { previewView }, modifier = modifier.fillMaxSize())
    }

    /**
     * Takes a still with the camera on screen and returns it as a base64 JPEG,
     * upright and no larger than [MAX_DIMENSION] on its longer side, or an empty
     * string when no preview is running. Blocks until the photo is ready, so it
     * is called off the main thread.
     */
    @JvmStatic
    fun captureBase64(): String {
        val capture = currentCapture.get() ?: return ""
        val latch = CountDownLatch(1)
        val result = AtomicReference("")
        val failure = AtomicReference<Throwable?>(null)

        capture.takePicture(captureExecutor, object : ImageCapture.OnImageCapturedCallback() {
            override fun onCaptureSuccess(image: ImageProxy) {
                try {
                    result.set(encode(image))
                } catch (error: Throwable) {
                    failure.set(error)
                } finally {
                    image.close()
                    latch.countDown()
                }
            }

            override fun onError(exception: ImageCaptureException) {
                failure.set(exception)
                latch.countDown()
            }
        })

        if (!latch.await(CAPTURE_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            throw IllegalStateException("Timed out taking the photo")
        }
        failure.get()?.let { throw it }
        Log.i(TAG, "captured base64Length=${result.get().length}")
        return result.get()
    }

    private fun encode(image: ImageProxy): String {
        val buffer = image.planes[0].buffer
        val jpeg = ByteArray(buffer.remaining()).also { buffer.get(it) }

        // Decoded at the smallest power-of-two reduction that still covers
        // MAX_DIMENSION, then scaled the rest of the way, so a 12MP frame is
        // never held in memory at full size.
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, bounds)
        var sampleSize = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sampleSize * 2) >= MAX_DIMENSION) {
            sampleSize *= 2
        }
        val decoded = BitmapFactory.decodeByteArray(
            jpeg, 0, jpeg.size,
            BitmapFactory.Options().apply { inSampleSize = sampleSize }
        ) ?: throw IllegalStateException("Could not read the photo")

        val longest = maxOf(decoded.width, decoded.height)
        val scale = if (longest > MAX_DIMENSION) MAX_DIMENSION.toFloat() / longest else 1f
        val matrix = Matrix().apply {
            postScale(scale, scale)
            // The sensor's frame is stored as the sensor sees it; the rotation
            // turns it the way the student held the phone.
            postRotate(image.imageInfo.rotationDegrees.toFloat())
        }
        val upright = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)

        val stream = ByteArrayOutputStream()
        upright.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, stream)
        if (upright !== decoded) upright.recycle()
        decoded.recycle()
        return Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
    }
}
