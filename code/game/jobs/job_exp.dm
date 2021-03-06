// Admin Verbs

/client/proc/cmd_admin_check_player_exp()	//Allows admins to determine who the newer players are.
	set category = "Admin"
	set name = "Check Player Playtime"
	if(!check_rights(R_ADMIN))
		return
	var/msg = "<html><head><title>Playtime Report</title></head><body>Playtime:<BR><UL>"
	for(var/client/C in clients)
		msg += "<LI> [key_name_admin(C.mob)]: <A href='?_src_=holder;getplaytimewindow=[C.mob.UID()]'>" + C.get_exp_living() + "</a></LI>"
	msg += "</UL></BODY></HTML>"
	src << browse(msg, "window=Player_playtime_check")


/datum/admins/proc/cmd_show_exp_panel(var/client/C)
	if(!C)
		to_chat(usr, "ERROR: Client not found.")
		return
	if(!check_rights(R_ADMIN))
		return
	var/body = "<html><head><title>Playtime for [C.key]</title></head><BODY><BR>Playtime:"
	body += C.get_exp_report()
	body += "</BODY></HTML>"
	usr << browse(body, "window=playerplaytime[C.ckey];size=550x615")


// Procs


/datum/job/proc/available_in_playtime(client/C)
	if(!C)
		return 0
	if(!exp_requirements || !exp_type)
		return 0
	if(!config.use_exp_restrictions)
		return 0
	if(config.use_exp_restrictions_admin_bypass && check_rights(R_ADMIN, 0, C.mob))
		return 0
	var/list/play_records = params2list(C.prefs.exp)
	var/isexempt = text2num(play_records[EXP_TYPE_EXEMPT])
	if(isexempt)
		return 0
	var/my_exp = text2num(play_records[get_exp_req_type()])
	var/job_requirement = text2num(get_exp_req_amount())
	if(my_exp >= job_requirement)
		return 0
	else
		return (job_requirement - my_exp)

/datum/job/proc/get_exp_req_amount()
	return exp_requirements

/datum/job/proc/get_exp_req_type()
	return exp_type

/mob/proc/get_exp_report()
	if(client)
		return client.get_exp_report()
	else
		return "[src] has no client."

/client/proc/get_exp_report()
	if(!config.use_exp_tracking)
		return "Tracking is disabled in the server configuration file."
	var/list/play_records = params2list(prefs.exp)
	if(!play_records.len)
		return "[key] has no records."
	var/return_text = "<UL>"
	var/list/exp_data = list()
	for(var/category in exp_jobsmap)
		if(text2num(play_records[category]))
			exp_data[category] = text2num(play_records[category])
		else
			exp_data[category] = 0
	for(var/dep in exp_data)
		if(exp_data[dep] > 0)
			if(dep == EXP_TYPE_EXEMPT)
				return_text += "<LI>Exempt (all jobs auto-unlocked)</LI>"
			else if(exp_data[EXP_TYPE_LIVING] > 0)
				var/my_pc = num2text(round(exp_data[dep]/exp_data[EXP_TYPE_LIVING]*100))
				return_text += "<LI>[dep]: [get_exp_format(exp_data[dep])] ([my_pc]%)</LI>"
			else
				return_text += "<LI>[dep]: [get_exp_format(exp_data[dep])] </LI>"
	if(config.use_exp_restrictions_admin_bypass && check_rights(R_ADMIN, 0, mob))
		return_text += "<LI>Admin</LI>"
	return_text += "</UL>"
	if(config.use_exp_restrictions)
		var/list/jobs_locked = list()
		var/list/jobs_unlocked = list()
		for(var/datum/job/job in job_master.occupations)
			if(job.exp_requirements && job.exp_type)
				if(!job.available_in_playtime(mob.client))
					jobs_unlocked += job.title
				else
					var/xp_req = job.get_exp_req_amount()
					jobs_locked += "[job.title] ([get_exp_format(text2num(play_records[job.get_exp_req_type()]))] / [get_exp_format(xp_req)] as [job.get_exp_req_type()])"
		if(jobs_unlocked.len)
			return_text += "<BR><BR>Jobs Unlocked:<UL><LI>"
			return_text += jobs_unlocked.Join("</LI><LI>")
			return_text += "</LI></UL>"
		if(jobs_locked.len)
			return_text += "<BR><BR>Jobs Not Unlocked:<UL><LI>"
			return_text += jobs_locked.Join("</LI><LI>")
			return_text += "</LI></UL>"
	return return_text


/client/proc/get_exp_living()
	var/list/play_records = params2list(prefs.exp)
	var/exp_living = text2num(play_records[EXP_TYPE_LIVING])
	return get_exp_format(exp_living)

/proc/get_exp_format(var/expnum)
	if(expnum > 60)
		return num2text(round(expnum / 60)) + "h"
	else if(expnum > 0)
		return num2text(expnum) + "m"
	else
		return "none"

/proc/update_exp(var/mins, var/ann = 0)
	if(!establish_db_connection())
		return -1
	spawn(0)
		for(var/client/L in clients)
			if(L.inactivity >= (10 MINUTES))
				continue
			spawn(0)
				L.update_exp_client(mins, ann)
			sleep(10)

/client/proc/update_exp_client(var/minutes, var/announce_changes = 0)
	if(!src ||!ckey)
		return
	var/DBQuery/exp_read = dbcon.NewQuery("SELECT exp FROM [format_table_name("player")] WHERE ckey='[ckey]'")
	if(!exp_read.Execute())
		var/err = exp_read.ErrorMsg()
		log_game("SQL ERROR during exp_update_client read. Error : \[[err]\]\n")
		message_admins("SQL ERROR during exp_update_client read. Error : \[[err]\]\n")
		return
	var/list/read_records = list()
	var/hasread = 0
	while(exp_read.NextRow())
		read_records = params2list(exp_read.item[1])
		hasread = 1
	if(!hasread)
		return
	var/list/play_records = list()
	for(var/rtype in exp_jobsmap)
		if(text2num(read_records[rtype]))
			play_records[rtype] = text2num(read_records[rtype])
		else
			play_records[rtype] = 0
	if(mob.stat == CONSCIOUS && mob.mind.assigned_role)
		play_records[EXP_TYPE_LIVING] += minutes
		if(announce_changes)
			to_chat(mob,"<span class='notice'>You got: [minutes] Living EXP!")
		for(var/category in exp_jobsmap)
			if(exp_jobsmap[category]["titles"])
				if(mob.mind.assigned_role in exp_jobsmap[category]["titles"])
					play_records[category] += minutes
					if(announce_changes)
						to_chat(mob,"<span class='notice'>You got: [minutes] [category] EXP!")
		if(mob.mind.special_role)
			play_records[EXP_TYPE_SPECIAL] += minutes
			if(announce_changes)
				to_chat(mob,"<span class='notice'>You got: [minutes] Special EXP!")
	else if(isobserver(mob))
		play_records[EXP_TYPE_GHOST] += minutes
		if(announce_changes)
			to_chat(mob,"<span class='notice'>You got: [minutes] Ghost EXP!")
	else
		return
	var/new_exp = list2params(play_records)
	prefs.exp = new_exp
	new_exp = sanitizeSQL(new_exp)
	var/DBQuery/update_query = dbcon.NewQuery("UPDATE [format_table_name("player")] SET exp = '[new_exp]' WHERE ckey='[ckey]'")
	if(!update_query.Execute())
		var/err = update_query.ErrorMsg()
		log_game("SQL ERROR during exp_update_client write. Error : \[[err]\]\n")
		message_admins("SQL ERROR during exp_update_client write. Error : \[[err]\]\n")
		return

/hook/roundstart/proc/exptimer()
	if(!config.sql_enabled || !config.use_exp_tracking)
		return 1
	spawn(0)
		while(TRUE)
			sleep(5 MINUTES)
			update_exp(5,0)
	return 1
