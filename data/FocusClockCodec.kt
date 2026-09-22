package it.notes.ecosystem.data
import it.notes.ecosystem.domain.*
import org.json.JSONObject
object FocusClockCodec {
    fun encode(c:FocusClock):String {c.validate();return JSONObject().put("sessionId",c.sessionId).put("taskId",c.taskId)
        .put("seconds",c.durationSeconds).put("deadline",c.deadline).put("pausedMillis",c.pausedMillis ?: JSONObject.NULL)
        .put("phase",c.phase.name).put("workMinutes",c.workMinutes).put("shortBreak",c.shortBreakMinutes)
        .put("longBreak",c.longBreakMinutes).put("blocks",c.completedBlocks).toString()}
    fun decode(text:String):FocusClock {val o=JSONObject(text)
        return FocusClock(o.getString("sessionId"),o.getString("taskId"),o.getLong("seconds"),o.getLong("deadline"),
            if(o.isNull("pausedMillis")) null else o.getLong("pausedMillis"),FocusPhase.valueOf(o.optString("phase","WORK")),
            o.optInt("workMinutes",(o.getLong("seconds")/60).toInt().coerceIn(1,120)),o.optInt("shortBreak",5),o.optInt("longBreak",15),o.optInt("blocks",0)).validate()
    }
}
