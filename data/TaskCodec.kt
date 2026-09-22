package it.notes.ecosystem.data

import it.notes.ecosystem.domain.*
import org.json.JSONArray
import org.json.JSONObject

object TaskCodec {

    fun json(task: TaskDetails?): Any =
        task?.let { t ->
            validateTask(t)

            JSONObject()
                .put("due", t.due ?: JSONObject.NULL)
                .put("priority", t.priority)
                .put("repeat", t.repeat.name)
                .put("completedAt", t.completedAt ?: JSONObject.NULL)
                .put("linkedNoteId", t.linkedNoteId ?: JSONObject.NULL)
                .put("reminderTime", t.reminderTime ?: JSONObject.NULL)
                .put("stage", t.stage.name)
                .put("reminderAt", t.reminderAt ?: JSONObject.NULL)
                .put("reminderZone", t.reminderZone ?: JSONObject.NULL)
                .put(
                    "focusHistory",
                    JSONArray().apply {
                        t.focusHistory.forEach {
                            put(
                                JSONObject()
                                    .put("id", it.id)
                                    .put("seconds", it.seconds)
                                    .put("endedAt", it.endedAt)
                            )
                        }
                    }
                )
                .put("focusSeconds", t.focusSeconds)
                .put("focusReceipts", JSONArray(t.focusReceipts))
                .put("completedCycles", t.completedCycles)

                // Planner Pro 0.23.
                .put("plannedDate", t.plannedDate ?: JSONObject.NULL)
                .put("plannedTime", t.plannedTime ?: JSONObject.NULL)
                .put("plannedMinutes", t.plannedMinutes)
        } ?: JSONObject.NULL

    fun encode(task: TaskDetails?): String? =
        task?.let { json(it).toString() }

    fun decode(raw: String?): TaskDetails? =
        raw?.let {
            read(JSONObject(it))
        }

    fun read(value: Any): TaskDetails? {
        if (value === JSONObject.NULL) return null

        val o = value as? JSONObject
            ?: error("Attività non valida.")

        fun str(key: String): String =
            o.get(key) as? String
                ?: error("Campo attività non testuale: $key")

        fun num(key: String): Long {
            val valueNumber = o.get(key)
            require(valueNumber is Int || valueNumber is Long)
            return (valueNumber as Number).toLong()
        }

        fun optional(key: String): String? =
            if (!o.has(key) || o.get(key) === JSONObject.NULL) {
                null
            } else {
                str(key)
            }

        val priority = num("priority")
        require(priority in 0..3)

        val cycles = num("completedCycles")
        require(cycles in 0..1000000)

        val receipts = o.getJSONArray("focusReceipts")
        require(receipts.length() <= 200)

        val plannedMinutes =
            if (o.has("plannedMinutes")) {
                num("plannedMinutes").toInt()
            } else {
                PlannerPro.DEFAULT_BLOCK_MINUTES
            }

        return validateTask(
            TaskDetails(
                due = optional("due"),
                priority = priority.toInt(),
                repeat = RepeatRule.valueOf(str("repeat")),
                completedAt =
                    if (o.get("completedAt") === JSONObject.NULL) null
                    else num("completedAt"),
                linkedNoteId = optional("linkedNoteId"),
                focusSeconds = num("focusSeconds"),
                focusReceipts =
                    (0 until receipts.length()).map {
                        receipts.get(it) as? String
                            ?: error("Sessione non valida.")
                    },
                completedCycles = cycles.toInt(),
                stage =
                    if (o.has("stage")) {
                        TaskStage.valueOf(str("stage"))
                    } else {
                        TaskStage.TODO
                    },
                reminderAt =
                    if (
                        !o.has("reminderAt") ||
                        o.get("reminderAt") === JSONObject.NULL
                    ) {
                        null
                    } else {
                        num("reminderAt")
                    },
                reminderZone =
                    if (
                        !o.has("reminderZone") ||
                        o.get("reminderZone") === JSONObject.NULL
                    ) {
                        null
                    } else {
                        str("reminderZone")
                    },
                focusHistory =
                    if (!o.has("focusHistory")) {
                        emptyList()
                    } else {
                        o.getJSONArray("focusHistory").let { history ->
                            require(history.length() <= 200)

                            (0 until history.length()).map { i ->
                                val item = history.getJSONObject(i)

                                fun number(key: String): Long {
                                    val number = item.get(key)
                                    require(number is Long || number is Int)
                                    return (number as Number).toLong()
                                }

                                FocusSession(
                                    id = item.get("id") as? String
                                        ?: error("Sessione non valida."),
                                    seconds = number("seconds"),
                                    endedAt = number("endedAt"),
                                )
                            }
                        }
                    },
                reminderTime =
                    if (
                        !o.has("reminderTime") ||
                        o.get("reminderTime") === JSONObject.NULL
                    ) {
                        null
                    } else {
                        str("reminderTime")
                    },

                // Campi nuovi: default sicuri per JSON <= 0.22.
                plannedDate = optional("plannedDate"),
                plannedTime = optional("plannedTime"),
                plannedMinutes = plannedMinutes,
            )
        )
    }
}
