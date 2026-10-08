package teacher.minute

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.media.ExifInterface
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream

/**
 * A photo made ready to upload: an upright JPEG no larger than a given size on
 * its longer side. Shared by the question camera (`AndroidQuestionCamera`) and
 * the photo picker (`AndroidImagePickerManager`).
 */
object AndroidPhotoScaler {
    /**
     * [jpeg] scaled to [maxDimension] and turned upright. A camera frame says
     * how far to turn it with [rotationDegrees]; a photo from the gallery
     * leaves that null and is turned by the orientation stored in it.
     */
    fun scaledJpeg(jpeg: ByteArray, maxDimension: Int, quality: Int, rotationDegrees: Int? = null): ByteArray {
        // Decoded at the smallest power-of-two reduction that still covers
        // maxDimension, then scaled the rest of the way, so a 12MP photo is
        // never held in memory at full size.
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, bounds)
        var sampleSize = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sampleSize * 2) >= maxDimension) {
            sampleSize *= 2
        }
        val decoded = BitmapFactory.decodeByteArray(
            jpeg, 0, jpeg.size,
            BitmapFactory.Options().apply { inSampleSize = sampleSize }
        ) ?: throw IllegalStateException("Could not read the photo")

        val longest = maxOf(decoded.width, decoded.height)
        val scale = if (longest > maxDimension) maxDimension.toFloat() / longest else 1f
        val matrix = Matrix().apply {
            postScale(scale, scale)
            if (rotationDegrees != null) {
                postRotate(rotationDegrees.toFloat())
            } else {
                postConcat(storedOrientation(jpeg))
            }
        }
        val upright = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
        val opaque = onWhite(upright)

        val stream = ByteArrayOutputStream()
        opaque.compress(Bitmap.CompressFormat.JPEG, quality, stream)
        if (opaque !== upright) opaque.recycle()
        if (upright !== decoded) upright.recycle()
        decoded.recycle()
        return stream.toByteArray()
    }

    /**
     * A JPEG has no transparency, and a transparent screenshot's clear pixels
     * would come out black, under text that is often black too.
     */
    private fun onWhite(bitmap: Bitmap): Bitmap {
        if (!bitmap.hasAlpha()) return bitmap
        val opaque = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
        Canvas(opaque).apply {
            drawColor(Color.WHITE)
            drawBitmap(bitmap, 0f, 0f, null)
        }
        return opaque
    }

    /**
     * The turn, or flip, a photo's EXIF asks for. Decoding ignores it, and the
     * re-encoded JPEG carries none, so it has to be drawn in.
     */
    private fun storedOrientation(jpeg: ByteArray): Matrix {
        val orientation = try {
            ExifInterface(ByteArrayInputStream(jpeg))
                .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        } catch (error: Exception) {
            ExifInterface.ORIENTATION_NORMAL
        }
        return Matrix().apply {
            when (orientation) {
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> postScale(-1f, 1f)
                ExifInterface.ORIENTATION_ROTATE_180 -> postRotate(180f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> postScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> { postRotate(90f); postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_ROTATE_90 -> postRotate(90f)
                ExifInterface.ORIENTATION_TRANSVERSE -> { postRotate(-90f); postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_ROTATE_270 -> postRotate(270f)
            }
        }
    }
}
