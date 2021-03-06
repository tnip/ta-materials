----------------------------------------------------------------------------------------------------
-- Author: nip2
-- tl;dr: Loads users from CSV into Confluence
----------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------------
-- MAKE CHANGES BELOW
----------------------------------------------------------------------------------------------------

set domain to "https://gitlab-beta.engr.illinois.edu"
--set csv_path to "/Volumes/Documents/Users/tnip/Documents/cs421-roster-20160118.csv"
set csv_path to "/Volumes/Documents/Users/tnip/test.csv"


----------------------------------------------------------------------------------------------------
-- Overview
----------------------------------------------------------------------------------------------------
-- Most of this code up top is lifted from Stack Overflow.
-- There's a comment somewhere down below delineating where my code starts.
--
-- Your CSV file needs to have UNIX newlines versus the stuff Excel spits out
--   that's one singular line. To do that, run the following:
--      cat {$original_roster} | sed s/^M/\r\n/g > {$new_file}
--   where $original_roster is the roster file from my.cs
--   and $new_file is your new file location.
--
-- Once that's done, you'll want to replace the file path in
--   "set csvText to read" with the path to $new_file.
--
-- We assume that:
--    field1 in the CSV is the Net ID
--    field2 in the CSV is their UIN (to be used as default password)
--    field4 in the CSV is their Last Name
--    field5 in the CSV is their First Name
--    there is NO header row
--     **** IMPORTANT: You must also be LOGGED INTO Confluence's Admin panel! ****
----------------------------------------------------------------------------------------------------
-- What happens is this script opens up $new_file and for each record,
--  fires up a new tab in Google Chrome and executes some JavaScript to
--  fill in the corresponding form fields in Confluence and submits it.
----------------------------------------------------------------------------------------------------


(* Assumes that the CSV text adheres to the convention:
   Records are delimited by LFs or CRLFs (but CRs are also allowed here).
   The last record in the text may or may not be followed by an LF or CRLF (or CR).
   Fields in the same record are separated by commas (unless specified differently by parameter).
   The last field in a record must not be followed by a comma.
   Trailing or leading spaces in unquoted fields are not ignored (unless so specified by parameter).
   Fields containing quoted text are quoted in their entirety, any space outside them being ignored.
   Fields enclosed in double-quotes are to be taken verbatim, except for any included double-quote pairs, which are to be translated as double-quote characters.

   No other variations are currently supported. *)

on csvToList(csvText, implementation)
	-- The 'implementation' parameter must be a record. Leave it empty ({}) for the default assumptions: ie. comma separator, leading and trailing spaces in unquoted fields not to be trimmed. Otherwise it can have a 'separator' property with a text value (eg. {separator:tab}) and/or a 'trimming' property with a boolean value ({trimming:true}).
	set {separator:separator, trimming:trimming} to (implementation & {separator:",", trimming:false})
	
	script o -- Lists for fast access.
		property qdti : getTextItems(csvText, "\"")
		property currentRecord : {}
		property possibleFields : missing value
		property recordList : {}
	end script
	
	-- o's qdti is a list of the CSV's text items, as delimited by double-quotes.
	-- Assuming the convention mentioned above, the number of items is always odd.
	-- Even-numbered items (if any) are quoted field values and don't need parsing.
	-- Odd-numbered items are everything else. Empty strings in odd-numbered slots
	-- (except at the beginning and end) indicate escaped quotes in quoted fields.
	
	set astid to AppleScript's text item delimiters
	set qdtiCount to (count o's qdti)
	set quoteInProgress to false
	considering case
		repeat with i from 1 to qdtiCount by 2 -- Parse odd-numbered items only.
			set thisBit to item i of o's qdti
			if ((count thisBit) > 0) or (i is qdtiCount) then
				-- This is either a non-empty string or the last item in the list, so it doesn't
				-- represent a quoted quote. Check if we've just been dealing with any.
				if (quoteInProgress) then
					-- All the parts of a quoted field containing quoted quotes have now been
					-- passed over. Coerce them together using a quote delimiter.
					set AppleScript's text item delimiters to "\""
					set thisField to (items a thru (i - 1) of o's qdti) as string
					-- Replace the reconstituted quoted quotes with literal quotes.
					set AppleScript's text item delimiters to "\"\""
					set thisField to thisField's text items
					set AppleScript's text item delimiters to "\""
					-- Store the field in the "current record" list and cancel the "quote in progress" flag.
					set end of o's currentRecord to thisField as string
					set quoteInProgress to false
				else if (i > 1) then
					-- The preceding, even-numbered item is a complete quoted field. Store it.
					set end of o's currentRecord to item (i - 1) of o's qdti
				end if
				
				-- Now parse this item's field-separator-delimited text items, which are either non-quoted fields or stumps from the removal of quoted fields. Any that contain line breaks must be further split to end one record and start another. These could include multiple single-field records without field separators.
				set o's possibleFields to getTextItems(thisBit, separator)
				set possibleFieldCount to (count o's possibleFields)
				repeat with j from 1 to possibleFieldCount
					set thisField to item j of o's possibleFields
					if ((count thisField each paragraph) > 1) then
						-- This "field" contains one or more line endings. Split it at those points.
						set theseFields to thisField's paragraphs
						-- With each of these end-of-record fields except the last, complete the field list for the current record and initialise another. Omit the first "field" if it's just the stub from a preceding quoted field.
						repeat with k from 1 to (count theseFields) - 1
							set thisField to item k of theseFields
							if ((k > 1) or (j > 1) or (i is 1) or ((count trim(thisField, true)) > 0)) then set end of o's currentRecord to trim(thisField, trimming)
							set end of o's recordList to o's currentRecord
							set o's currentRecord to {}
						end repeat
						-- With the last end-of-record "field", just complete the current field list if the field's not the stub from a following quoted field.
						set thisField to end of theseFields
						if ((j < possibleFieldCount) or ((count thisField) > 0)) then set end of o's currentRecord to trim(thisField, trimming)
					else
						-- This is a "field" not containing a line break. Insert it into the current field list if it's not just a stub from a preceding or following quoted field.
						if (((j > 1) and ((j < possibleFieldCount) or (i is qdtiCount))) or ((j is 1) and (i is 1)) or ((count trim(thisField, true)) > 0)) then set end of o's currentRecord to trim(thisField, trimming)
					end if
				end repeat
				
				-- Otherwise, this item IS an empty text representing a quoted quote.
			else if (quoteInProgress) then
				-- It's another quote in a field already identified as having one. Do nothing for now.
			else if (i > 1) then
				-- It's the first quoted quote in a quoted field. Note the index of the
				-- preceding even-numbered item (the first part of the field) and flag "quote in
				-- progress" so that the repeat idles past the remaining part(s) of the field.
				set a to i - 1
				set quoteInProgress to true
			end if
		end repeat
	end considering
	
	-- At the end of the repeat, store any remaining "current record".
	if (o's currentRecord is not {}) then set end of o's recordList to o's currentRecord
	set AppleScript's text item delimiters to astid
	
	return o's recordList
end csvToList

-- Get the possibly more than 4000 text items from a text.
on getTextItems(txt, delim)
	set astid to AppleScript's text item delimiters
	set AppleScript's text item delimiters to delim
	set tiCount to (count txt's text items)
	set textItems to {}
	repeat with i from 1 to tiCount by 4000
		set j to i + 3999
		if (j > tiCount) then set j to tiCount
		set textItems to textItems & text items i thru j of txt
	end repeat
	set AppleScript's text item delimiters to astid
	
	return textItems
end getTextItems

-- Trim any leading or trailing spaces from a string.
on trim(txt, trimming)
	if (trimming) then
		repeat with i from 1 to (count txt) - 1
			if (txt begins with space) then
				set txt to text 2 thru -1 of txt
			else
				exit repeat
			end if
		end repeat
		repeat with i from 1 to (count txt) - 1
			if (txt ends with space) then
				set txt to text 1 thru -2 of txt
			else
				exit repeat
			end if
		end repeat
		if (txt is space) then set txt to ""
	end if
	
	return txt
end trim

(* below was written by tnip *)

set csvText to read csv_path

set l to csvToList(csvText, {separator:","}, {trimming:true})

repeat with student_record in l
	tell application "Google Chrome"
		open location domain & "/projects/new?namespace_id=644"
		tell active tab of window 1
			repeat while loading is true
				delay 0.2
			end repeat
			execute javascript "document.getElementById('project_path').value='" & item 1 in student_record & "';
                                document.getElementById('new_project').submit();"
			delay 0.2
			display dialog item 1 in student_record
		end tell
	end tell
end repeat
