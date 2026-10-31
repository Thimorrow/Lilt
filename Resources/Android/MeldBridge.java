import android.content.Context;
import android.graphics.Bitmap;
import android.media.MediaMetadata;
import android.media.session.MediaController;
import android.media.session.MediaSessionManager;
import android.media.session.PlaybackState;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Base64;
import java.io.ByteArrayOutputStream;
import java.util.ArrayList;
import java.util.List;
import org.json.JSONObject;

public final class MeldBridge {
    private static final String PACKAGE = "com.meld.app";

    public static void main(String[] args) {
        try {
            String command = args.length == 1 ? args[0] : "";
            if (!command.equals("snapshot") && !command.equals("play") && !command.equals("pause") && !command.equals("next") && !command.equals("previous")) {
                throw new IllegalArgumentException("unsupportedCommand");
            }
            Looper.prepareMainLooper();
            Class<?> threadClass = Class.forName("android.app.ActivityThread");
            Object thread = threadClass.getMethod("systemMain").invoke(null);
            Context context = (Context) threadClass.getMethod("getSystemContext").invoke(thread);
            // app_process does not receive the media framework setup performed by Zygote.
            Class<?> services = Class.forName("android.media.MediaServiceManager");
            Class.forName("android.media.MediaFrameworkPlatformInitializer")
                .getMethod("setMediaServiceManager", services)
                .invoke(null, services.getConstructor().newInstance());
            MediaSessionManager manager = (MediaSessionManager) context.getSystemService(Context.MEDIA_SESSION_SERVICE);
            List<MediaController> matches = new ArrayList<>();
            for (MediaController controller : manager.getActiveSessions(null)) {
                if (PACKAGE.equals(controller.getPackageName())) matches.add(controller);
            }
            if (matches.size() > 1) throw new IllegalStateException("ambiguousSession");
            if (matches.isEmpty()) {
                if (!command.equals("snapshot")) throw new IllegalStateException("noSession");
                System.out.println(new JSONObject().put("availability", "empty"));
                System.exit(0);
            }
            MediaController controller = matches.get(0);
            JSONObject before = snapshot(controller, false);
            if (!command.equals("snapshot")) {
                if (!before.optBoolean(capability(command))) throw new IllegalStateException("unsupportedAction");
                MediaController.TransportControls controls = controller.getTransportControls();
                switch (command) {
                    case "play": controls.play(); break;
                    case "pause": controls.pause(); break;
                    case "next": controls.skipToNext(); break;
                    case "previous": controls.skipToPrevious(); break;
                }
                long deadline = SystemClock.elapsedRealtime() + 3000;
                boolean confirmed = false;
                do {
                    SystemClock.sleep(100);
                    if (confirmed(command, before, snapshot(controller, false))) { confirmed = true; break; }
                } while (SystemClock.elapsedRealtime() < deadline);
                if (!confirmed) throw new IllegalStateException("notConfirmed");
            }
            JSONObject result = snapshot(controller, true);
            if (!command.equals("snapshot")) result.put("confirmedCommand", command);
            System.out.println(result);
        } catch (Throwable error) {
            try {
                String code = error.getMessage();
                if (code == null || !code.matches("[A-Za-z]+")) code = "bridgeUnavailable";
                System.out.println(new JSONObject().put("availability", "unavailable").put("code", code));
            } catch (Exception ignored) { System.out.println("{\"availability\":\"unavailable\",\"code\":\"bridgeUnavailable\"}"); }
        }
        System.exit(0);
    }

    private static String capability(String command) {
        switch (command) {
            case "play": return "canPlay";
            case "pause": return "canPause";
            case "next": return "canNext";
            default: return "canPrevious";
        }
    }

    private static boolean confirmed(String command, JSONObject before, JSONObject after) {
        if (!after.optString("availability").equals("ready")) return false;
        if (command.equals("play")) return after.optBoolean("playing");
        if (command.equals("pause")) return !after.optBoolean("playing") && !after.optBoolean("buffering");
        if (!before.optString("id").equals(after.optString("id")) || !before.optString("queueID").equals(after.optString("queueID"))) return true;
        return command.equals("previous") && before.optDouble("elapsed") > 1.5 && after.optDouble("elapsed") < 1.5;
    }

    private static JSONObject snapshot(MediaController controller, boolean includeCover) throws Exception {
        MediaMetadata metadata = controller.getMetadata();
        PlaybackState playback = controller.getPlaybackState();
        if (metadata == null || playback == null) return new JSONObject().put("availability", "empty");
        String title = metadata.getString(MediaMetadata.METADATA_KEY_TITLE);
        if (title == null || title.trim().isEmpty()) title = metadata.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE);
        if (title == null || title.trim().isEmpty()) return new JSONObject().put("availability", "empty");
        String artist = metadata.getString(MediaMetadata.METADATA_KEY_ARTIST);
        if (artist == null) artist = metadata.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE);
        if (artist == null) artist = "";
        String album = metadata.getString(MediaMetadata.METADATA_KEY_ALBUM);
        if (album == null) album = "";
        String id = metadata.getString(MediaMetadata.METADATA_KEY_MEDIA_ID);
        if (id == null || id.isEmpty()) id = title + "\u001f" + artist;
        int state = playback.getState();
        if (state == PlaybackState.STATE_ERROR) throw new IllegalStateException("playbackError");
        boolean playing = state == PlaybackState.STATE_PLAYING;
        boolean buffering = state == PlaybackState.STATE_BUFFERING || state == PlaybackState.STATE_CONNECTING || state == PlaybackState.STATE_SKIPPING_TO_NEXT || state == PlaybackState.STATE_SKIPPING_TO_PREVIOUS || state == PlaybackState.STATE_SKIPPING_TO_QUEUE_ITEM;
        double duration = Math.max(0, metadata.getLong(MediaMetadata.METADATA_KEY_DURATION) / 1000.0);
        double elapsed = Math.max(0, playback.getPosition() / 1000.0);
        if (playing && playback.getLastPositionUpdateTime() > 0) {
            elapsed += Math.max(0, SystemClock.elapsedRealtime() - playback.getLastPositionUpdateTime()) / 1000.0 * Math.max(0, playback.getPlaybackSpeed());
        }
        if (duration > 0) elapsed = Math.min(duration, elapsed);
        long actions = playback.getActions();
        JSONObject result = new JSONObject().put("availability", "ready").put("package", PACKAGE)
            .put("id", id).put("title", title).put("artist", artist).put("album", album)
            .put("queueID", String.valueOf(playback.getActiveQueueItemId()))
            .put("duration", duration).put("elapsed", elapsed).put("playing", playing).put("buffering", buffering)
            .put("speed", Math.max(0, playback.getPlaybackSpeed()))
            .put("canPlay", (actions & (PlaybackState.ACTION_PLAY | PlaybackState.ACTION_PLAY_PAUSE)) != 0)
            .put("canPause", (actions & (PlaybackState.ACTION_PAUSE | PlaybackState.ACTION_PLAY_PAUSE)) != 0)
            .put("canNext", (actions & PlaybackState.ACTION_SKIP_TO_NEXT) != 0)
            .put("canPrevious", (actions & PlaybackState.ACTION_SKIP_TO_PREVIOUS) != 0);
        if (includeCover) {
            Bitmap art = metadata.getBitmap(MediaMetadata.METADATA_KEY_ART);
            if (art == null) art = metadata.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART);
            if (art == null) art = metadata.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON);
            if (art != null && !art.isRecycled() && art.getWidth() > 0 && art.getHeight() > 0) {
                float scale = Math.min(1, 160f / Math.max(art.getWidth(), art.getHeight()));
                Bitmap small = Bitmap.createScaledBitmap(art, Math.max(1, Math.round(art.getWidth() * scale)), Math.max(1, Math.round(art.getHeight() * scale)), true);
                ByteArrayOutputStream bytes = new ByteArrayOutputStream();
                small.compress(Bitmap.CompressFormat.JPEG, 80, bytes);
                if (bytes.size() <= 65536) result.put("cover", "data:image/jpeg;base64," + Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP));
                if (small != art) small.recycle();
            }
        }
        return result;
    }
}
