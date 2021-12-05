#define MAX_FLAGS_STRING_LENGTH 32
#define MAX_AUTH_FLAGS_STRING_LENGTH 12
#define MAX_ACCOUNT_NAME_LENGTH 64
#define MAX_PASSWORD_HASH_LENGTH 34
#define INVALID_CALLER_ID -1 // AccessManager_AccessAdded() won't be called with this

enum _:ACCOUNT_DATA_STRUCT {
	ACCOUNT_DATA__ROWID, // not used in local mode
	ACCOUNT_DATA__AUTHID[MAX_NAME_LENGTH],
	ACCOUNT_DATA__PASSWORD[MAX_PASSWORD_HASH_LENGTH],
	ACCOUNT_DATA__NAME[MAX_ACCOUNT_NAME_LENGTH],
	ACCOUNT_DATA__ACCESS_FLAGS,
	ACCOUNT_DATA__AUTH_FLAGS,
	ACCOUNT_DATA__EXPIRE,
	ACCOUNT_DATA__CREATED // not used in local mode
}

forward AccessManager_AccessAdded(iUserID, iCallerID);
forward client_admin(pPlayer, bitAccessFlags);
forward amxx_admin_access(pPlayer, bitAccessFlags, iExpireTimeStamp);

native admin_expired(pPlayer);
native amxbans_get_expired(pPlayer);
native adminload_get_expired(pPlayer);

native AccessManager_ReAuthPlayer(pPlayer);

// To use this native, first see 'ADD_ACCESS_FEATURE' define in AccessManager.sma
// pPlayer - player index (pass 0 if player is not connected)
// szAuthID - player authid
// szFlags - flags to give
// iMinutes - minutes to add
// iCaller - caller indentifier that will be passed to AccessManager_AccessAdded()
//	when all is done (pass INVALID_CALLER_ID if you don't need callback)
native AccessManager_AddAccess(pPlayer, const szAuthID[], const szFlags[], iDays, iCaller = INVALID_CALLER_ID);