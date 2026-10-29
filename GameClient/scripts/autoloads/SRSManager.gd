extends Node

# Quantum-inspired SRS logic adapted from prototype
# Structure of a record:
# {
#    "meaning_strength": 0.2, "reading_strength": 0.2,
#    "hesitation_score": 0.0, "average_reaction_time": 0.0, "total_attempts": 0
# }

func create_default_record() -> Dictionary:
	return {
		"meaning_strength": 0.2,
		"reading_strength": 0.2,
		"hesitation_score": 0.0,
		"average_reaction_time": 0.0,
		"total_attempts": 0
	}

func get_or_create_record(kanji: String) -> Dictionary:
	var rec = Database.get_memory_record(kanji)
	if rec.is_empty():
		return create_default_record()
	return rec

func get_overall_strength(kanji: String) -> float:
	var rec = get_or_create_record(kanji)
	return (rec["meaning_strength"] + rec["reading_strength"]) / 2.0

func update_record(kanji: String, q_type: String, is_correct: bool, reaction_time: float, hesitation_count: int):
	var rec = get_or_create_record(kanji)
	
	rec["total_attempts"] += 1
	var attempts = rec["total_attempts"]
	
	if attempts == 1:
		rec["average_reaction_time"] = reaction_time
		rec["hesitation_score"] = float(hesitation_count)
	else:
		rec["average_reaction_time"] = (rec["average_reaction_time"] * (attempts - 1) + reaction_time) / float(attempts)
		rec["hesitation_score"] = (rec["hesitation_score"] * (attempts - 1) + float(hesitation_count)) / float(attempts)

	# Target reaction time: ~2 seconds. Faster is better.
	var time_factor = max(0.2, 1.0 - (reaction_time / 10.0))
	# Hesitation factor: less changing of mind is better
	var hesitation_factor = max(0.3, 1.0 - (hesitation_count * 0.25))
	
	var base_change = 0.25
	
	if is_correct:
		# Reward
		var change = base_change * time_factor * hesitation_factor
		if q_type == "meaning":
			rec["meaning_strength"] = min(1.0, rec["meaning_strength"] + change)
		elif q_type == "reading":
			rec["reading_strength"] = min(1.0, rec["reading_strength"] + change)
	else:
		# Penalty
		var change = base_change * 1.5
		if q_type == "meaning":
			rec["meaning_strength"] = max(0.0, rec["meaning_strength"] - change)
		elif q_type == "reading":
			rec["reading_strength"] = max(0.0, rec["reading_strength"] - change)

	Database.update_memory_record(kanji, rec)

func is_mastered(kanji: String) -> bool:
	return get_overall_strength(kanji) >= 0.85
