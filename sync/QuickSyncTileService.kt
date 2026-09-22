package it.notes.ecosystem.sync

import android.os.Build
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import it.notes.ecosystem.NotesApplication

@RequiresApi(Build.VERSION_CODES.N)
class QuickSyncTileService : TileService() {
    override fun onClick() {
        super.onClick()
        (application as? NotesApplication)?.githubSync?.schedule()
    }
}
