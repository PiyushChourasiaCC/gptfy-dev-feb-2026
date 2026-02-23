public with sharing class AIRecentRecordsController {
    
    public class RecentRecord {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String objectType;
        @AuraEnabled public String details;
        @AuraEnabled public String iconName;
        
        public RecentRecord(Id id, String name, String type, String details, String icon) {
            this.recordId = id;
            this.name = name;
            this.objectType = type;
            this.details = details;
            this.iconName = icon;
        }
    }
    
    /**
     * Get recently viewed records for relevant object types
     * @return List of RecentRecord objects
     */
    @AuraEnabled(cacheable=true)
    public static List<RecentRecord> getRecentRecords() {
        List<RecentRecord> results = new List<RecentRecord>();
        
        try {
            // Query RecentlyViewed for Accounts, Contacts, Opportunities, and Cases
            List<RecentlyViewed> recentItems = [
                SELECT Id, Name, Type, LastViewedDate
                FROM RecentlyViewed
                WHERE Type IN ('Account', 'Contact', 'Opportunity', 'Case')
                WITH USER_MODE
                ORDER BY LastViewedDate DESC
                LIMIT 10
            ];
            
            for (RecentlyViewed item : recentItems) {
                String iconName = getIconName(item.Type);
                String details = getRelativeTime(item.LastViewedDate);
                
                results.add(new RecentRecord(
                    item.Id,
                    item.Name,
                    item.Type,
                    details,
                    iconName
                ));
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error fetching recent records: ' + e.getMessage());
        }
        
        return results;
    }
    
    /**
     * Get icon name based on object type
     */
    private static String getIconName(String objectType) {
        switch on objectType {
            when 'Account' {
                return 'standard:account';
            }
            when 'Contact' {
                return 'standard:contact';
            }
            when 'Opportunity' {
                return 'standard:opportunity';
            }
            when 'Case' {
                return 'standard:case';
            }
            when else {
                return 'standard:record';
            }
        }
    }
    
    /**
     * Convert datetime to relative time string
     */
    private static String getRelativeTime(Datetime dt) {
        if (dt == null) return '';
        
        Long secondsAgo = (Datetime.now().getTime() - dt.getTime()) / 1000;
        
        if (secondsAgo < 60) {
            return 'Viewed just now';
        } else if (secondsAgo < 3600) {
            Long mins = secondsAgo / 60;
            return 'Viewed ' + mins + ' min' + (mins > 1 ? 's' : '') + ' ago';
        } else if (secondsAgo < 86400) {
            Long hours = secondsAgo / 3600;
            return 'Viewed ' + hours + ' hour' + (hours > 1 ? 's' : '') + ' ago';
        } else if (secondsAgo < 604800) {
            Long days = secondsAgo / 86400;
            return 'Viewed ' + days + ' day' + (days > 1 ? 's' : '') + ' ago';
        } else {
            return 'Viewed ' + dt.format('MMM d');
        }
    }
}