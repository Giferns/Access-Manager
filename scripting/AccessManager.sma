/* Changelog:
	1.0.0 (03.03.2021):
		* First release
*/

// Some mechanics was taken from 'Admin Loader' by Neygomon
new const PLUGIN_VERSION[] = "1.0.0"

#include <amxmodx>
#include <amxmisc>
#include <sqlx>
#include <reapi>
#include <time>
#include <access_manager>

/* -------------------- */

// NOTE: To use this feature you need to add field `ingame` (int type) to `amx_amxadmins` table !
//#define ADD_ACCESS_FEATURE

new const CONFIG_FILENAME[] = "AccessManager.cfg"
new const LOCAL_FILENAME[] = "am_users.ini"
new const BACKUP_FILENAME[] = "am_users_sql_backup.ini"
new const ERR_LOG_FILENAME[] = "AccessManager_Errors.log"
new const LONG_QUERY_FILENAME[] = "AccessManager_LongQuery.log"
stock const ADD_ACCESS_LOG_FILENAME[] = "AccessManager_AddAccess.log"

/* -------------------- */

#define chx charsmax
#define chx_len(%0) charsmax(%0) - iLen
#define CreateMF CreateMultiForward
#define INVALID_SERVER_ID -1
#define MAX_LANG_KEY_LENGTH 3
#define MAX_SQL_ACC_LEN 64
#define MAX_TIMESTAMP_NUM_LENGTH 11

enum {
	QUERY__PRUNE_TABLE_1,
	QUERY__PRUNE_TABLE_2,
	QUERY__PRUNE_TABLE_3,
	QUERY__LOAD_ADMINS,
	QUERY__UPDATE_ROW,
	QUERY__INSERT_ROW_1,
	QUERY__INSERT_ROW_2,
	QUERY__INSERT_ROW_3
}

enum _:SQL_DATA_STRUCT {
	SQL_DATA__QUERY_TYPE,
	SQL_DATA__PLAYER_USERID,
	SQL_DATA__REQUEST_ID,
	SQL_DATA__CALLER,
	SQL_DATA__ADMIN_ID
}

enum _:AUTH_TYPE_ENUM {
	AUTH_BY_NAME,
	AUTH_BY_STEAMID,
	AUTH_BY_IP
}

enum _:PCVAR_ENUM {
	PCVAR__HOST,
	PCVAR__USER,
	PCVAR__PASSWORD,
	PCVAR__DATABASE,
	PCVAR__SERVER_IP
}

enum _:CVAR_ENUM {
	CVAR__PASSWORD_FIELD[32],
	CVAR__DEFAULT_FLAGS[32],
	CVAR__RELOAD_ANYONE,
	CVAR__RELOAD_COOLDOWN,
	Float:CVAR_F__LONG_QUERY_TIME,
	CVAR__PRUNE_EXPIRED,
	CVAR__LOCAL_MODE
}

new g_pCvar[PCVAR_ENUM]
new g_eCvar[CVAR_ENUM]
new g_fwdClientAdmin
new g_fwdAdminAccess
stock g_fwdAccessAdded
new g_iExpireTimeStamp[MAX_PLAYERS + 1]
new g_eSqlData[SQL_DATA_STRUCT]
new g_eUserData[ACCOUNT_DATA_STRUCT]
new bool:g_bPluginEnded
new Handle:g_hSqlTuple
new g_szServerAddress[MAX_IP_WITH_PORT_LENGTH]
new Array:g_aAccounts
new g_szQuery[2048]
new g_iAccCount
new g_iServerId = INVALID_SERVER_ID

/* -------------------- */

public plugin_init() {
	register_plugin("Access Manager", PLUGIN_VERSION, "mx?!")
	register_dictionary("access_manager.txt")

	register_concmd("amx_reloadadmins", "concmd_ReloadAdmins", ADMIN_CFG)

	bind_cvar_string( "amx_password_field", "_pw", FCVAR_PROTECTED,
		.bind = g_eCvar[CVAR__PASSWORD_FIELD], .maxlen = chx(g_eCvar[CVAR__PASSWORD_FIELD]) );

	bind_cvar_string( "amx_default_access", "z", FCVAR_PROTECTED,
		.bind = g_eCvar[CVAR__DEFAULT_FLAGS], .maxlen = chx(g_eCvar[CVAR__DEFAULT_FLAGS]) );

	bind_cvar_num("am_local_mode", "0", FCVAR_PROTECTED, .bind = g_eCvar[CVAR__LOCAL_MODE])
	bind_cvar_num("am_allow_reload_to_anyone", "0", FCVAR_PROTECTED, .bind = g_eCvar[CVAR__RELOAD_ANYONE])
	bind_cvar_num("am_reloadadmins_cooldown", "30", FCVAR_PROTECTED, .bind = g_eCvar[CVAR__RELOAD_COOLDOWN])
	bind_cvar_float("am_long_query_time", "10", FCVAR_PROTECTED, .bind = g_eCvar[CVAR_F__LONG_QUERY_TIME])
#if defined ADD_ACCESS_FEATURE
	bind_cvar_num("am_prune_expired", "0", FCVAR_PROTECTED, .bind = g_eCvar[CVAR__PRUNE_EXPIRED])
	g_fwdAccessAdded = CreateMF("AccessManager_AccessAdded", ET_IGNORE, FP_CELL, FP_CELL)
#endif

	g_pCvar[PCVAR__HOST] = create_cvar("am_host", "", FCVAR_PROTECTED)
	g_pCvar[PCVAR__USER] = create_cvar("am_user", "", FCVAR_PROTECTED)
	g_pCvar[PCVAR__PASSWORD] = create_cvar("am_password", "", FCVAR_PROTECTED)
	g_pCvar[PCVAR__DATABASE] = create_cvar("am_database", "", FCVAR_PROTECTED)
	g_pCvar[PCVAR__SERVER_IP] = create_cvar("am_server_ip", "", FCVAR_PROTECTED)

	new szPath[PLATFORM_MAX_PATH]
	new iLen = get_configsdir(szPath, chx(szPath))
	formatex(szPath[iLen], chx_len(szPath), "/%s", CONFIG_FILENAME)
	server_cmd("exec %s", szPath)

	g_fwdClientAdmin = CreateMF("client_admin", ET_IGNORE, FP_CELL, FP_CELL)
	g_fwdAdminAccess = CreateMF("amxx_admin_access", ET_IGNORE, FP_CELL, FP_CELL, FP_CELL)

	RegisterHookChain(RG_CBasePlayer_SetClientUserInfoName, "CBasePlayer_SetClientUserInfoName_Post", true)

	g_aAccounts = ArrayCreate(ACCOUNT_DATA_STRUCT, 32)

	set_task(1.0, "task_InitSystem")
}

/* -------------------- */

// fresh bans
public fbans_sql_connected(Handle:hSqlTuple) {
	g_hSqlTuple = hSqlTuple

	new szIP[MAX_IP_LENGTH], szPort[6]
	get_cvar_string("fb_server_ip", szIP, chx(szIP))
	get_cvar_string("fb_server_port", szPort, chx(szPort))
	formatex(g_szServerAddress, chx(g_szServerAddress), "%s:%s", szIP, szPort)
}

/* -------------------- */

// lite bans
public lite_bans_sql_init(Handle:hSqlTuple) {
	g_hSqlTuple = hSqlTuple

	get_cvar_string("lb_server_ip", g_szServerAddress, chx(g_szServerAddress))
}

/* -------------------- */

/* AMXBANS if outdated and even forward execution don't fit in this logic. So don't ask me to support it!
public amxbans_sql_initialized() {} */

/* -------------------- */

public task_InitSystem() {
	func_LoadBackUp()

	if(!g_hSqlTuple) {
		func_CreateTuple()
	}

	set_pcvar_string(g_pCvar[PCVAR__PASSWORD], "*** PROTECTED ***")

	func_InitSQL()
}

/* -------------------- */

func_CreateTuple() {
	new szHost[MAX_SQL_ACC_LEN]
	get_pcvar_string(g_pCvar[PCVAR__HOST], szHost, chx(szHost))

	if(!szHost[0]) {
		return
	}

	new szUser[MAX_SQL_ACC_LEN], szPass[MAX_SQL_ACC_LEN], szDB[MAX_SQL_ACC_LEN]
	get_pcvar_string(g_pCvar[PCVAR__USER], szUser, chx(szUser))
	get_pcvar_string(g_pCvar[PCVAR__PASSWORD], szPass, chx(szPass))
	get_pcvar_string(g_pCvar[PCVAR__DATABASE], szDB, chx(szDB))
	get_pcvar_string(g_pCvar[PCVAR__SERVER_IP], g_szServerAddress, chx(g_szServerAddress))

	if(!SQL_SetAffinity("mysql")) {
		log_to_file(ERR_LOG_FILENAME, "Failed to use 'mysql' as DB driver")
		return
	}

	g_hSqlTuple = SQL_MakeDbTuple(szHost, szUser, szPass, szDB)
	SQL_SetCharset(g_hSqlTuple, "utf8")
}

/* -------------------- */

func_InitSQL() {
	if(!g_hSqlTuple || g_eCvar[CVAR__LOCAL_MODE]) {
		return
	}

	new iDay; date(.day = iDay)

	if(!g_eCvar[CVAR__PRUNE_EXPIRED] || get_cvar_num("_am_rows_pruned") == iDay) {
		func_LoadAdminsSql()
		return
	}

	set_pcvar_num(create_cvar("_am_rows_pruned", ""), iDay)

	formatex( g_szQuery, chx(g_szQuery),
		"SELECT `id` FROM `amx_amxadmins` WHERE `ingame` = 1 AND `days` != 0 AND `expired` <= UNIX_TIMESTAMP(NOW())"
	);

	func_MakeQuery(QUERY__PRUNE_TABLE_1)
}

/* -------------------- */

func_LoadBackUp() {
	new szPath[PLATFORM_MAX_PATH]

	new iLen = get_configsdir(szPath, chx(szPath))
	formatex(szPath[iLen], chx_len(szPath), "/%s", g_eCvar[CVAR__LOCAL_MODE] ? LOCAL_FILENAME : BACKUP_FILENAME)

	new hFile = fopen(szPath, "r")

	if(!hFile) {
		log_to_file( ERR_LOG_FILENAME, "Can't %s '%s' !", file_exists(szPath) ? "read" : "find",
			g_eCvar[CVAR__LOCAL_MODE] ? LOCAL_FILENAME : BACKUP_FILENAME );

		return
	}

	g_iAccCount = 0
	ArrayClear(g_aAccounts)
	admins_flush()

	new szText[256], szAccessFlags[MAX_FLAGS_STRING_LENGTH], szAuthFlags[MAX_AUTH_FLAGS_STRING_LENGTH],
		szExpired[32], iExpired, iCurrentTime = get_systime();

	new szRowId[14], szCreated[MAX_TIMESTAMP_NUM_LENGTH]

	while(!feof(hFile)) {
		fgets(hFile, szText, chx(szText))

		if(szText[0] != '"') {
			continue
		}

		parse(szText,
			szRowId, chx(szRowId),
				g_eUserData[ACCOUNT_DATA__AUTHID], chx(g_eUserData[ACCOUNT_DATA__AUTHID]),
					g_eUserData[ACCOUNT_DATA__PASSWORD], chx(g_eUserData[ACCOUNT_DATA__PASSWORD]),
						szAccessFlags, chx(szAccessFlags),
							szAuthFlags, chx(szAuthFlags),
								g_eUserData[ACCOUNT_DATA__NAME], chx(g_eUserData[ACCOUNT_DATA__NAME]),
									szExpired, chx(szExpired),
										szCreated, chx(szCreated)
		);

		if(!g_eCvar[CVAR__LOCAL_MODE]) {
			iExpired = str_to_num(szExpired)
		}
		else {
			if(equal(szExpired, "lifetime")) {
				iExpired = 0
			}
			else {
				iExpired = parse_time(szExpired, "%d.%m.%Y - %H:%M:%S")
			}
		}

		if(iExpired && iExpired <= iCurrentTime) {
			continue
		}

		g_eUserData[ACCOUNT_DATA__ROWID] = str_to_num(szRowId)
		g_eUserData[ACCOUNT_DATA__EXPIRE] = iExpired
		g_eUserData[ACCOUNT_DATA__CREATED] = str_to_num(szCreated)
		g_eUserData[ACCOUNT_DATA__ACCESS_FLAGS] = read_flags(szAccessFlags)
		g_eUserData[ACCOUNT_DATA__AUTH_FLAGS] = read_flags(szAuthFlags)
		ArrayPushArray(g_aAccounts, g_eUserData)
		g_iAccCount++

		admins_push( g_eUserData[ACCOUNT_DATA__AUTHID], g_eUserData[ACCOUNT_DATA__PASSWORD],
			g_eUserData[ACCOUNT_DATA__ACCESS_FLAGS], g_eUserData[ACCOUNT_DATA__AUTH_FLAGS] );
	}

	fclose(hFile)

	log_amx("Loaded %i account(s) from '%s'", g_iAccCount, g_eCvar[CVAR__LOCAL_MODE] ? LOCAL_FILENAME : BACKUP_FILENAME)

	func_AuthAllPlayers()
}

/* -------------------- */

func_LoadAdminsSql() {
	formatex( g_szQuery, chx(g_szQuery),
		"SELECT \
		`a`.`id`, \
		`a`.`steamid`, \
		`a`.`password`, \
		`a`.`nickname`, \
		`a`.`access`, \
		`a`.`flags`, \
		`a`.`expired`, \
		`a`.`created`, \
		`b`.`custom_flags` \
		FROM `amx_amxadmins` AS `a`, `amx_admins_servers` AS `b` \
		WHERE `b`.`admin_id` = `a`.`id` \
                AND `b`.`server_id` = (SELECT `id` FROM `amx_serverinfo` WHERE `address` = '%s') \
                AND (`a`.`days` = '0' OR `a`.`expired` > UNIX_TIMESTAMP(NOW()))",

		g_szServerAddress
	);

	func_MakeQuery(QUERY__LOAD_ADMINS)
}

/* -------------------- */

public SQL_Handler(iFailState, Handle:hQueryHandle, szError[], iErrorCode, eSqlData[], iDataSize, Float:fQueryTime) {
	if(g_bPluginEnded) {
		return
	}

	if(iFailState != TQUERY_SUCCESS) {
		if(iFailState == TQUERY_CONNECT_FAILED)	{
			log_to_file(ERR_LOG_FILENAME, "[SQL] Can't connect to server [%.2f]", fQueryTime)
			log_to_file(ERR_LOG_FILENAME, "[SQL] Error #%i, %s", iErrorCode, szError)
		}
		else /*if(iFailState == TQUERY_QUERY_FAILED)*/ {
			SQL_GetQueryString(hQueryHandle, g_szQuery, chx(g_szQuery))
			log_to_file(ERR_LOG_FILENAME, "[SQL] Query error!")
			log_to_file(ERR_LOG_FILENAME, "[SQL] Error #%i, %s", iErrorCode, szError)
			log_to_file(ERR_LOG_FILENAME, "[SQL] Query: %s", g_szQuery)
		}

		return
	}

	/* --- */

	if(fQueryTime > g_eCvar[CVAR_F__LONG_QUERY_TIME]) {
		SQL_GetQueryString(hQueryHandle, g_szQuery, chx(g_szQuery))
		log_to_file(LONG_QUERY_FILENAME, "[%.2f] %s", fQueryTime, g_szQuery)
	}

	switch(eSqlData[SQL_DATA__QUERY_TYPE]) {
		/* --- */

		case QUERY__LOAD_ADMINS: {
			new szAccessFlags[MAX_FLAGS_STRING_LENGTH], szAuthFlags[MAX_AUTH_FLAGS_STRING_LENGTH]

			new szPath[PLATFORM_MAX_PATH]

			new iLen = get_configsdir(szPath, chx(szPath))
			formatex(szPath[iLen], chx_len(szPath), "/%s", BACKUP_FILENAME)

			new hFile = fopen(szPath, "w")

			if(!hFile) {
				log_to_file(ERR_LOG_FILENAME, "Can't %s '%s' !", file_exists(szPath) ? "write" : "find", BACKUP_FILENAME)
			}
			else {
				get_time("%d.%m.%Y - %H:%M:%S", szAccessFlags, chx(szAccessFlags))
				fprintf(hFile, "; 'Access Manager' SQL accounts list backup file. Backup date: %s^n^n", szAccessFlags)
			}

			g_iAccCount = 0
			ArrayClear(g_aAccounts)
			admins_flush()

			new iNumResults = SQL_NumResults(hQueryHandle)

			while(iNumResults) {
				g_eUserData[ACCOUNT_DATA__ROWID] = SQL_ReadResult(hQueryHandle, 0)
				SQL_ReadResult(hQueryHandle, 1, g_eUserData[ACCOUNT_DATA__AUTHID], chx(g_eUserData[ACCOUNT_DATA__AUTHID]))
				SQL_ReadResult(hQueryHandle, 2, g_eUserData[ACCOUNT_DATA__PASSWORD], chx(g_eUserData[ACCOUNT_DATA__PASSWORD]))
				SQL_ReadResult(hQueryHandle, 3, g_eUserData[ACCOUNT_DATA__NAME], chx(g_eUserData[ACCOUNT_DATA__NAME]))
				SQL_ReadResult(hQueryHandle, 8, szAccessFlags, chx(szAccessFlags))
				trim(szAccessFlags)

				if(!szAccessFlags[0]) {
					SQL_ReadResult(hQueryHandle, 4, szAccessFlags, chx(szAccessFlags))
				}

				g_eUserData[ACCOUNT_DATA__ACCESS_FLAGS] = read_flags(szAccessFlags)
				SQL_ReadResult(hQueryHandle, 5, szAuthFlags, chx(szAuthFlags))
				g_eUserData[ACCOUNT_DATA__AUTH_FLAGS] = read_flags(szAuthFlags)
				g_eUserData[ACCOUNT_DATA__EXPIRE] = SQL_ReadResult(hQueryHandle, 6)
				g_eUserData[ACCOUNT_DATA__CREATED] = SQL_ReadResult(hQueryHandle, 7)

				if(hFile) {
					fprintf( hFile, "^"%i^" ^"%s^" ^"%s^" ^"%s^" ^"%s^" ^"%s^" ^"%i^" ^"%i^"^n",
						g_eUserData[ACCOUNT_DATA__ROWID],
						g_eUserData[ACCOUNT_DATA__AUTHID], g_eUserData[ACCOUNT_DATA__PASSWORD], szAccessFlags,
						szAuthFlags, g_eUserData[ACCOUNT_DATA__NAME], g_eUserData[ACCOUNT_DATA__EXPIRE],
						g_eUserData[ACCOUNT_DATA__CREATED]
					);
				}

				ArrayPushArray(g_aAccounts, g_eUserData)
				g_iAccCount++

				admins_push( g_eUserData[ACCOUNT_DATA__AUTHID], g_eUserData[ACCOUNT_DATA__PASSWORD],
					g_eUserData[ACCOUNT_DATA__ACCESS_FLAGS], g_eUserData[ACCOUNT_DATA__AUTH_FLAGS] );

				iNumResults--
				SQL_NextRow(hQueryHandle)
			}

			if(hFile) {
				fclose(hFile)
			}

			log_amx("[%.2f] Loaded %i account(s) from DB", fQueryTime, g_iAccCount)

			func_AuthAllPlayers()
		}

		/* --- */
	#if defined ADD_ACCESS_FEATURE
		case QUERY__PRUNE_TABLE_1: {
			new iNumResults = SQL_NumResults(hQueryHandle)

			log_to_file(ADD_ACCESS_LOG_FILENAME, "%i rows to prune", iNumResults)

			if(!iNumResults) {
				func_LoadAdminsSql()
				return
			}

			new bool:bHasSome

			new iLen = formatex(g_szQuery, chx(g_szQuery), "DELETE FROM `amx_amxadmins` WHERE `id` IN(")

			while(iNumResults) {
				iLen += formatex( g_szQuery[iLen], chx_len(g_szQuery), "%s%i",
					bHasSome ? "," : "", SQL_ReadResult(hQueryHandle, 0) );

				bHasSome = true

				/* -- */

				iNumResults--
				SQL_NextRow(hQueryHandle)
			}

			formatex(g_szQuery[iLen], chx_len(g_szQuery), ")")

			func_MakeQuery(QUERY__PRUNE_TABLE_2)

			/* --- */

			SQL_Rewind(hQueryHandle)

			iNumResults = SQL_NumResults(hQueryHandle)

			bHasSome = false

			iLen = formatex(g_szQuery, chx(g_szQuery), "DELETE FROM `amx_admins_servers` WHERE `admin_id` IN(")

			while(iNumResults) {
				iLen += formatex( g_szQuery[iLen], chx_len(g_szQuery), "%s%i",
					bHasSome ? "," : "", SQL_ReadResult(hQueryHandle, 0) );

				bHasSome = true

				/* -- */

				iNumResults--
				SQL_NextRow(hQueryHandle)
			}

			formatex(g_szQuery[iLen], chx_len(g_szQuery), ")")

			func_MakeQuery(QUERY__PRUNE_TABLE_3)
		}

		/* --- */

		case QUERY__PRUNE_TABLE_3: {
			//log_to_file(ADD_ACCESS_LOG_FILENAME, "%i rows deleted", SQL_AffectedRows(hQueryHandle))
			func_LoadAdminsSql()
		}

		/* --- */

		case QUERY__UPDATE_ROW: {
			new iRequestID = eSqlData[SQL_DATA__REQUEST_ID]

			if(SQL_AffectedRows(hQueryHandle)) {
				log_to_file(ADD_ACCESS_LOG_FILENAME, "Query %i (UPDATE) completed", iRequestID)

				func_LoadAdminsSql()
			}
			else { // Probably account was deleted in the table (here we are working from the cache)
				log_to_file( ADD_ACCESS_LOG_FILENAME,
					"Error! Query %i (UPDATE) completed, but SQL_AffectedRows() returned 0 !",	iRequestID );
			}

			func_CallAccessAddedFwd(eSqlData[SQL_DATA__PLAYER_USERID], eSqlData[SQL_DATA__CALLER])
		}

		/* --- */

		case QUERY__INSERT_ROW_1: {
			log_to_file( ADD_ACCESS_LOG_FILENAME,
				"Query %i (INSERT #1) completed, continue", eSqlData[SQL_DATA__REQUEST_ID] );

			for(new i; i < SQL_DATA_STRUCT; i++) {
				g_eSqlData[i] = eSqlData[i]
			}

			g_eSqlData[SQL_DATA__ADMIN_ID] = SQL_GetInsertId(hQueryHandle)

			if(g_iServerId != INVALID_SERVER_ID) {
				func_FinalizeInsert()
				return
			}

			formatex( g_szQuery, chx(g_szQuery),
				"SELECT `id` FROM `amx_serverinfo` WHERE `address` = '%s' LIMIT 1", g_szServerAddress );

			func_MakeQuery(QUERY__INSERT_ROW_2)
		}

		/* --- */

		case QUERY__INSERT_ROW_2: {
			new iRequestID = eSqlData[SQL_DATA__REQUEST_ID]

			if(!SQL_NumResults(hQueryHandle)) {
				log_to_file( ADD_ACCESS_LOG_FILENAME,
					"Error! Query %i (INSERT #2) completed, but SQL_NumResults() returned 0 !", iRequestID );

				return
			}

			g_iServerId = SQL_ReadResult(hQueryHandle, 0)

			log_to_file( ADD_ACCESS_LOG_FILENAME,
				"Query %i (INSERT #2) completed, finilize", iRequestID );

			for(new i; i < SQL_DATA_STRUCT; i++) {
				g_eSqlData[i] = eSqlData[i]
			}

			func_FinalizeInsert()
		}

		/* --- */

		case QUERY__INSERT_ROW_3: {
			log_to_file( ADD_ACCESS_LOG_FILENAME,
				"Query %i (INSERT #3) completed", eSqlData[SQL_DATA__REQUEST_ID] );

			func_LoadAdminsSql()

			func_CallAccessAddedFwd(eSqlData[SQL_DATA__PLAYER_USERID], eSqlData[SQL_DATA__CALLER])
		}
	#endif // ADD_ACCESS_FEATURE
	}
}

/* -------------------- */

stock func_CallAccessAddedFwd(iUserID, iCaller) {
	if(iCaller != INVALID_CALLER_ID) {
		ExecuteForward(g_fwdAccessAdded, _, iUserID, iCaller)
	}
}

/* -------------------- */

stock func_FinalizeInsert() {
	formatex( g_szQuery, chx(g_szQuery),
		"INSERT INTO `amx_admins_servers` \
			(`admin_id`,`server_id`,`custom_flags`,`use_static_bantime`) \
		VALUES \
		(%i,%i,'','no')",

		g_eSqlData[SQL_DATA__ADMIN_ID], g_iServerId
	);

	func_MakeQuery(QUERY__INSERT_ROW_3)
}

/* -------------------- */

func_AuthAllPlayers() {
	new pPlayers[MAX_PLAYERS], iPlCount
	get_players(pPlayers, iPlCount)

	for(new i; i < iPlCount; i++) {
		func_AuthPlayer(pPlayers[i])
	}
}

/* -------------------- */

func_AuthPlayer(pPlayer) {
	g_iExpireTimeStamp[pPlayer] = -1

	remove_user_flags(pPlayer)

	static szName[MAX_NAME_LENGTH], szAuthID[MAX_AUTHID_LENGTH], szIP[MAX_IP_LENGTH]

	get_user_name(pPlayer, szName, chx(szName))
	get_user_authid(pPlayer, szAuthID, chx(szAuthID))
	get_user_ip(pPlayer, szIP, chx(szIP), .without_port = 1)

	new iAuthCount, bitAccessFlags, bitAuthFlags, iAuthType

	/*enum _:AUTH_TYPE_ENUM {
		AUTH_BY_NAME,
		AUTH_BY_STEAMID,
		AUTH_BY_IP
	}

	static const szAuthTypes[AUTH_TYPE_ENUM][] = { // lang keys
		"ACCESS_MANAGER__NAME",
		"ACCESS_MANAGER__STEAMID",
		"ACCESS_MANAGER__IP"
	}*/

	for(new i; i < g_iAccCount; i++) {
		ArrayGetArray(g_aAccounts, i, g_eUserData)

		bitAuthFlags = g_eUserData[ACCOUNT_DATA__AUTH_FLAGS]

		if(bitAuthFlags & FLAG_AUTHID) {
			if(
				szAuthID[11] != g_eUserData[ACCOUNT_DATA__AUTHID][11] // STEAM_X:X:X[X] or STEAM_XX:X:[X]
					||
				!equal(szAuthID, g_eUserData[ACCOUNT_DATA__AUTHID])
			) {
				continue
			}

			iAuthType = AUTH_BY_STEAMID
		}
		else if(bitAuthFlags & FLAG_IP) {
			if(szIP[0] != g_eUserData[ACCOUNT_DATA__AUTHID][0] || !equal(szIP, g_eUserData[ACCOUNT_DATA__AUTHID])) {
				continue
			}

			iAuthType = AUTH_BY_IP
		}
		else {
			if(
				/*szName[0] != g_eUserData[ACCOUNT_DATA__AUTHID][0]
					|| */
				!equali(szName, g_eUserData[ACCOUNT_DATA__AUTHID])
			) {
				continue
			}

			iAuthType = AUTH_BY_NAME
		}

		if(!(bitAuthFlags & FLAG_NOPASS)) {
			static szHash[MAX_PASSWORD_HASH_LENGTH], szPassword[33]

			if(g_eCvar[CVAR__LOCAL_MODE]) {
				get_user_info(pPlayer, g_eCvar[CVAR__PASSWORD_FIELD], szHash, chx(szHash))
			}
			else {
				get_user_info(pPlayer, g_eCvar[CVAR__PASSWORD_FIELD], szPassword, chx(szPassword))
				hash_string(szPassword, Hash_Md5, szHash, chx(szHash))
			}

			if(!equal(szHash, g_eUserData[ACCOUNT_DATA__PASSWORD])) {
				if(!(bitAuthFlags & FLAG_KICK)) {
					continue
				}

				engclient_print(pPlayer, engprint_console, "%l", "ACCESS_MANAGER__KICK_INFO_1", g_eCvar[CVAR__PASSWORD_FIELD])

				engclient_print(pPlayer, engprint_console, "%l %l", "ACCESS_MANAGER__KICK_INFO_2",
					(iAuthType != AUTH_BY_NAME) ? "ACCESS_MANAGER__VISIT_SITE" : "ACCESS_MANAGER__CHANGE_NAME" );

				/* Bug. engclient_print() doesn't print anything
				server_cmd( "kick #%i ^"%L^"", get_user_userid(pPlayer),
					pPlayer, "ACCESS_MANAGER__ACCESS_DENIED",
					pPlayer, szAuthTypes[iAuthType] );*/

				/* Bad idea to kick player in putinserver()
				rh_drop_client( pPlayer,
					fmt( "%L",
						pPlayer, "ACCESS_MANAGER__ACCESS_DENIED",
						pPlayer, szAuthTypes[iAuthType]
					)
				);*/

				new iData[1]; iData[0] = iAuthType
				set_task(0.1, "task_KickPlayer", get_user_userid(pPlayer), iData, sizeof(iData))

				log_amx( "Login: ^"%s<%s><%s>^" kicked due to invalid password '%s' (account ^"%s^")",
					szName, szAuthID, szIP, g_eCvar[CVAR__LOCAL_MODE] ? szHash : szPassword, g_eUserData[ACCOUNT_DATA__AUTHID] );

				return
			}
		}

		new iBitFlags = g_eUserData[ACCOUNT_DATA__ACCESS_FLAGS]
		new iExpireTimeStamp = g_eUserData[ACCOUNT_DATA__EXPIRE]

		if(!iExpireTimeStamp || (g_iExpireTimeStamp[pPlayer] && g_iExpireTimeStamp[pPlayer] < iExpireTimeStamp)) {
			g_iExpireTimeStamp[pPlayer] = iExpireTimeStamp
		}

		iAuthCount++
		bitAccessFlags |= iBitFlags
	}

	/* --- */

	static szFlags[MAX_FLAGS_STRING_LENGTH]

	if(!bitAccessFlags) {
		bitAccessFlags = read_flags(g_eCvar[CVAR__DEFAULT_FLAGS])
		copy(szFlags, chx(szFlags), g_eCvar[CVAR__DEFAULT_FLAGS])
	}
	else {
		get_flags(bitAccessFlags, szFlags, chx(szFlags))

		log_amx( "Login: ^"%s<%s><%s>^" authorized (auth count: %i) (access ^"%s^")",
			szName, szAuthID, szIP, iAuthCount, szFlags );
	}

	engclient_print(pPlayer, engprint_console, "%l", "ACCESS_MANAGER__ACCESS_INFO", szFlags)

	set_user_flags(pPlayer, bitAccessFlags)

	ExecuteForward(g_fwdClientAdmin, _, pPlayer, bitAccessFlags)
	ExecuteForward(g_fwdAdminAccess, _, pPlayer, bitAccessFlags, g_iExpireTimeStamp[pPlayer])
}

public task_KickPlayer(const iData[], iUserID) {
	new pPlayer = find_player("k", iUserID)

	if(!pPlayer) {
		return
	}

	static const szAuthTypes[AUTH_TYPE_ENUM][] = { // lang keys
		"ACCESS_MANAGER__NAME",
		"ACCESS_MANAGER__STEAMID",
		"ACCESS_MANAGER__IP"
	}

	new iAuthType = iData[0]

	rh_drop_client( pPlayer,
		fmt( "%L",
			pPlayer, "ACCESS_MANAGER__ACCESS_DENIED",
			pPlayer, szAuthTypes[iAuthType]
		)
	);
}

/* -------------------- */

public client_putinserver(pPlayer) {
	func_AuthPlayer(pPlayer)
}

/* -------------------- */

public CBasePlayer_SetClientUserInfoName_Post(pPlayer, szInfoBuffer[], szNewName[]) {
	if(is_user_connected(pPlayer) && GetHookChainReturn(ATYPE_BOOL)) {
		RequestFrame("func_AuthDelay", pPlayer) // as here player still have old name
	}
}

/* -------------------- */

public func_AuthDelay(pPlayer) {
	if(is_user_connected(pPlayer)) {
		func_AuthPlayer(pPlayer)
	}
}

/* -------------------- */

public concmd_ReloadAdmins(pPlayer, bitAccess) {
	new bool:bAdminAccess = (!pPlayer || !bitAccess || (get_user_flags(pPlayer) & bitAccess))

	if(!bAdminAccess && !g_eCvar[CVAR__RELOAD_ANYONE]) {
		console_print(pPlayer, "%l", "ACCESS_MANAGER__NO_ACCESS")
		return PLUGIN_HANDLED
	}

	static iLastUseTime

	new iSysTime = get_systime()
	new iSeconds = iSysTime - iLastUseTime

	if(!bAdminAccess && iLastUseTime && iSeconds < g_eCvar[CVAR__RELOAD_COOLDOWN]) {
		iSeconds = g_eCvar[CVAR__RELOAD_COOLDOWN] - iSeconds
		console_print(pPlayer, "%l", "ACCESS_MANAGER__STOP_SPAM", iSeconds / SECONDS_IN_MINUTE, iSeconds % SECONDS_IN_MINUTE)
		return PLUGIN_HANDLED
	}

	iLastUseTime = iSysTime

	console_print(pPlayer, "%L", func_GetLang(pPlayer), "ACCESS_MANAGER__RELOADING_ADMINS")

	new szAuthID[MAX_AUTHID_LENGTH]; get_user_authid(pPlayer, szAuthID, chx(szAuthID))
	new szIP[MAX_IP_LENGTH]; get_user_ip(pPlayer, szIP, chx(szIP), .without_port = 1)
	log_amx("<%n><%s><%s> used reloadadmins command", pPlayer, szAuthID, szIP)

	if(!g_hSqlTuple || g_eCvar[CVAR__LOCAL_MODE]) {
		func_LoadBackUp()
		return PLUGIN_HANDLED
	}

	func_LoadAdminsSql()

	return PLUGIN_HANDLED
}

/* -------------------- */

func_GetLang(pPlayer) {
	new szLang[MAX_LANG_KEY_LENGTH]

	if(pPlayer) {
		new iLen = get_user_info(pPlayer, "lang", szLang, chx(szLang))

		if(!iLen) {
			copy(szLang, chx(szLang), "ru")
		}
	}
	else {
		copy(szLang, chx(szLang), "en")
	}

	return szLang
}

/* -------------------- */

public plugin_end() {
	g_bPluginEnded = true
}

/* -------------------- */

public plugin_natives() {
	register_native("admin_expired", "admin_expired_callback")
	register_native("amxbans_get_expired", "admin_expired_callback") // support AmxBans RBS by SKAJIbnEJIb
	register_native("adminload_get_expired", "admin_expired_callback") // support Admin Load by Fant0M
	register_native("AccessManager_ReAuthPlayer", "_AccessManager_ReAuthPlayer")
#if defined ADD_ACCESS_FEATURE
	register_native("AccessManager_AddAccess", "_AccessManager_AddAccess")
#endif
}

/* -------------------- */

public admin_expired_callback(iPluginID, iParamCount) {
	enum { player = 1 }
	return g_iExpireTimeStamp[ get_param(player) ]
}

/* -------------------- */

public _AccessManager_ReAuthPlayer(iPluginID, iParamCount) {
	enum { player = 1 }
	new pPlayer = get_param(player)

	if(!is_user_connected(pPlayer)) {
		return 0
	}

	func_AuthPlayer(pPlayer)
	return 1
}

/* -------------------- */

#if defined ADD_ACCESS_FEATURE
	public _AccessManager_AddAccess(iPluginID, iParamCount) {
		enum { player = 1, authid, flags, minutes, caller }

		if(!g_hSqlTuple && !g_eCvar[CVAR__LOCAL_MODE]) {
			return -1
		}

		new pPlayer = get_param(player)

		new szAuthID[MAX_AUTHID_LENGTH]
		get_string(authid, szAuthID, chx(szAuthID))

		new szFlags[32]
		get_string(flags, szFlags, chx(szFlags))

		new iMinutes = get_param(minutes)
		new iCaller = get_param(caller)

		new iRequestID

		if(g_eCvar[CVAR__LOCAL_MODE]) {
			iRequestID = 1
		}
		else {
			iRequestID = random_num(2, 999999)
		}

		new szName[MAX_NAME_LENGTH * 3] = "unknown"
		new szIP[MAX_IP_LENGTH]

		new bitFlagsToSet = read_flags(szFlags)

		if(is_user_connected(pPlayer)) {
			get_user_name(pPlayer, szName, chx(szName))
			get_user_ip(pPlayer, szIP, chx(szIP), .without_port = 1)
			set_user_flags(pPlayer, bitFlagsToSet)
		}

		log_to_file( ADD_ACCESS_LOG_FILENAME, "Adding flags '%s' for %i minutes (caller %i) to <%s><%s><%s><query %i>",
			szFlags, iMinutes, iCaller, szName, szAuthID, szIP, iRequestID );

		if(g_eCvar[CVAR__LOCAL_MODE]) {
			iRequestID = func_AddToUsers(szAuthID, szFlags, szName, iMinutes, iRequestID)

			if(iRequestID != -1) {
				// get_user_userid() is safe to use for disconnected (returns -1)
				func_CallAccessAddedFwd(get_user_userid(pPlayer), iCaller)
			}

			return iRequestID
		}

		new iRowIdToExtend, iQueryType

		for(new i; i < g_iAccCount; i++) {
			ArrayGetArray(g_aAccounts, i, g_eUserData)

			if( !(g_eUserData[ACCOUNT_DATA__AUTH_FLAGS] & FLAG_AUTHID) ) {
				continue
			}

			if(
				szAuthID[11] != g_eUserData[ACCOUNT_DATA__AUTHID][11] // STEAM_X:X:X[X] or STEAM_XX:X:[X]
					||
				!equal(szAuthID, g_eUserData[ACCOUNT_DATA__AUTHID])
			) {
				continue
			}

			if(bitFlagsToSet == g_eUserData[ACCOUNT_DATA__ACCESS_FLAGS]) {
				iRowIdToExtend = g_eUserData[ACCOUNT_DATA__ROWID]
				break
			}
		}

		if(iRowIdToExtend) {
			if(!g_eUserData[ACCOUNT_DATA__EXPIRE]) {
				log_to_file( ADD_ACCESS_LOG_FILENAME,
					"Query %i, row #%i match and unlimited, no action required",
					iRequestID, iRowIdToExtend
				);

				// get_user_userid() is safe to use for disconnected (returns -1)
				func_CallAccessAddedFwd(get_user_userid(pPlayer), iCaller)

				return 0
			}

			log_to_file( ADD_ACCESS_LOG_FILENAME, "Query %i, row #%i match, do UPDATE",
				iRequestID, iRowIdToExtend );

			new iExpireTime

			if(iMinutes) {
				iExpireTime = g_eUserData[ACCOUNT_DATA__EXPIRE] + (iMinutes * SECONDS_IN_MINUTE)
			}

			formatex( g_szQuery, chx(g_szQuery),
				"UPDATE `amx_amxadmins` SET `expired` = %i WHERE `id` = %i LIMIT 1",

				iExpireTime, iRowIdToExtend
			);

			iQueryType = QUERY__UPDATE_ROW
		}
		else {
			log_to_file( ADD_ACCESS_LOG_FILENAME, "Query %i, do INSERT",
				iRequestID, iRowIdToExtend );

			mysql_escape_string(szName, chx(szName))

			new iSysTime = get_systime()

			new iExpireTime, iDays

			if(iMinutes) {
				iExpireTime = iSysTime + (iMinutes * SECONDS_IN_MINUTE)
				iDays = (iMinutes * SECONDS_IN_MINUTE) / SECONDS_IN_DAY
			}

			formatex( g_szQuery, chx(g_szQuery),
				"INSERT INTO `amx_amxadmins` \
					(`username`,`access`,`flags`,`steamid`,`nickname`,`ashow`,`created`,`expired`,`days`,`ingame`) \
						VALUES \
					('%s','%s','ce','%s','%s',0,%i,%i,%i,1)",

				szAuthID, szFlags, szAuthID, szName, iSysTime, iExpireTime, iDays
			);

			iQueryType = QUERY__INSERT_ROW_1
		}

		g_eSqlData[SQL_DATA__REQUEST_ID] = iRequestID
		g_eSqlData[SQL_DATA__CALLER] = iCaller
		g_eSqlData[SQL_DATA__PLAYER_USERID] = get_user_userid(pPlayer) // safe to use for disconnected (returns -1)

		func_MakeQuery(iQueryType)

		return iRequestID
	}
#endif // ADD_ACCESS_FEATURE

/* -------------------- */

stock func_AddToUsers(const szAuthID[], const szFlags[], const szName[], iMinutes, iRequestID) {
	new szPath[PLATFORM_MAX_PATH]

	new iLen = get_configsdir(szPath, chx(szPath))
	formatex(szPath[iLen], chx_len(szPath), "/%s", LOCAL_FILENAME)

	new hFile = fopen(szPath, "r")

	if(!hFile) {
		log_to_file(ERR_LOG_FILENAME, "Can't %s '%s' !", file_exists(szPath) ? "read" : "find", LOCAL_FILENAME)
		return -1
	}

	new szText[256], szAccessFlags[MAX_FLAGS_STRING_LENGTH], szAuthFlags[MAX_AUTH_FLAGS_STRING_LENGTH],
		szExpired[32];

	new bool:bUpdated, iLine

	while(!feof(hFile)) {
		fgets(hFile, szText, chx(szText))

		if(szText[0] != '"') {
			iLine++
			continue
		}

		parse(szText,
			"", "",
				g_eUserData[ACCOUNT_DATA__AUTHID], chx(g_eUserData[ACCOUNT_DATA__AUTHID]),
					g_eUserData[ACCOUNT_DATA__PASSWORD], chx(g_eUserData[ACCOUNT_DATA__PASSWORD]),
						szAccessFlags, chx(szAccessFlags),
							szAuthFlags, chx(szAuthFlags),
								g_eUserData[ACCOUNT_DATA__NAME], chx(g_eUserData[ACCOUNT_DATA__NAME]),
									szExpired, chx(szExpired)
		);

		if(equal(szAuthID, g_eUserData[ACCOUNT_DATA__AUTHID]) && equal(szFlags, szAccessFlags)) {
			if(equal(szExpired, "lifetime")) {
				log_to_file( ADD_ACCESS_LOG_FILENAME, "Account '%s' (line %i) already lifetime, no action required",
					g_eUserData[ACCOUNT_DATA__AUTHID], iLine + 1 );

				iRequestID = 0
				bUpdated = true
				break
			}

			if(!iMinutes) {
				szExpired = "lifetime"
			}
			else {
				new iExpired = parse_time(szExpired, "%d.%m.%Y - %H:%M:%S") + (iMinutes * SECONDS_IN_MINUTE)
				format_time(szExpired, chx(szExpired), "%d.%m.%Y - %H:%M:%S", iExpired)
			}

			formatex( szText, chx(szText), "^"^" ^"%s^"	^"^" ^"%s^" ^"%s^" ^"%s^" ^"%s^"",
				g_eUserData[ACCOUNT_DATA__AUTHID], szAccessFlags, szAuthFlags, g_eUserData[ACCOUNT_DATA__NAME], szExpired );

			write_file(szPath, szText, iLine)

			log_to_file( ADD_ACCESS_LOG_FILENAME, "Account '%s' (line %i) prolongated up to '%s'",
				g_eUserData[ACCOUNT_DATA__AUTHID], iLine + 1, szExpired );

			bUpdated = true
			break
		}

		iLine++
	}

	fclose(hFile)

	if(!bUpdated) {
		if(!iMinutes) {
			szExpired = "lifetime"
		}
		else {
			format_time(szExpired, chx(szExpired), "%d.%m.%Y - %H:%M:%S", get_systime() + (iMinutes * SECONDS_IN_MINUTE))
		}

		formatex( szText, chx(szText), "^"^" ^"%s^"	^"^" ^"%s^" ^"c^" ^"%s^" ^"%s^"",
			szAuthID, szFlags, szName, szExpired );

		write_file(szPath, szText, -1)

		log_to_file(ADD_ACCESS_LOG_FILENAME, "Inserted account '%s' up to '%s'", szAuthID, szExpired)
	}

	func_LoadBackUp()

	return iRequestID
}

/* -------------------- */

func_MakeQuery(iQueryType) {
	g_eSqlData[SQL_DATA__QUERY_TYPE] = iQueryType
	SQL_ThreadQuery(g_hSqlTuple, "SQL_Handler", g_szQuery, g_eSqlData, sizeof(g_eSqlData))
}

/* -------------------- */

stock bind_cvar_num(const cvar[], const value[], flags = FCVAR_NONE, const desc[] = "", bool:has_min = false, Float:min_val = 0.0, bool:has_max = false, Float:max_val = 0.0, &bind) {
	bind_pcvar_num(create_cvar(cvar, value, flags, desc, has_min, min_val, has_max, max_val), bind)
}

stock bind_cvar_float(const cvar[], const value[], flags = FCVAR_NONE, const desc[] = "", bool:has_min = false, Float:min_val = 0.0, bool:has_max = false, Float:max_val = 0.0, &Float:bind) {
	bind_pcvar_float(create_cvar(cvar, value, flags, desc, has_min, min_val, has_max, max_val), bind)
}

stock bind_cvar_string(const cvar[], const value[], flags = FCVAR_NONE, const desc[] = "", bool:has_min = false, Float:min_val = 0.0, bool:has_max = false, Float:max_val = 0.0, bind[], maxlen) {
	bind_pcvar_string(create_cvar(cvar, value, flags, desc, has_min, min_val, has_max, max_val), bind, maxlen)
}

stock bind_cvar_num_by_name(const szCvarName[], &iBindVariable) {
	bind_pcvar_num(get_cvar_pointer(szCvarName), iBindVariable)
}

stock mysql_escape_string(szString[], iMaxLen) {
	static const szReplaceWhat[][] = { "\\", "\x00", "\0", "\n", "\r", "\x1a", "'", "^"", "%" }
	static const szReplaceWith[][] = { "\\\\", "\\0", "\\0", "\\n", "\\r", "\\Z", "\'", "\^"", "\%" }

	for(new i; i < sizeof(szReplaceWhat); i++) {
		replace_string(szString, iMaxLen, szReplaceWhat[i], szReplaceWith[i])
	}
}