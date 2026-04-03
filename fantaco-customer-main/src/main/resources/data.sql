-- Database initialization script for Customer data
-- This script will be executed by Spring Boot on application startup
-- 150 US small business customers (CUST001 through CUST150)

INSERT INTO customer (customer_id, company_name, contact_name, contact_title, address, city, region, postal_code, country, phone, fax, contact_email, website, created_at, updated_at) VALUES
('CUST001', 'Brew & Bean Coffee Shop', 'Sarah Johnson', NULL, '123 Main Street, Portland, OR 97201', NULL, NULL, NULL, 'USA', '(555) 123-4567', NULL, 'sarah@brewandbean.com', 'www.brewandbean.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST002', 'Green Thumb Garden Center', 'Michael Chen', NULL, '456 Oak Avenue, Seattle, WA 98101', NULL, NULL, NULL, 'USA', '(555) 234-5678', NULL, 'michael@greenthumb.com', 'www.greenthumb.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST003', 'Tech Solutions IT', 'David Rodriguez', NULL, '789 Pine Street, San Francisco, CA 94101', NULL, NULL, NULL, 'USA', '(555) 345-6789', NULL, 'david@techsolutions.com', 'www.techsolutions.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST004', 'Sweet Treats Bakery', 'Emma Wilson', NULL, '321 Maple Drive, Denver, CO 80201', NULL, NULL, NULL, 'USA', '(555) 456-7890', NULL, 'emma@sweettreats.com', 'www.sweettreats.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST005', 'Urban Fitness Studio', 'James Thompson', NULL, '654 Elm Street, Austin, TX 78701', NULL, NULL, NULL, 'USA', '(555) 567-8901', NULL, 'james@urbanfitness.com', 'www.urbanfitness.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST006', 'Creative Design Co', 'Lisa Martinez', NULL, '987 Cedar Lane, Chicago, IL 60601', NULL, NULL, NULL, 'USA', '(555) 678-9012', NULL, 'lisa@creativedesign.com', 'www.creativedesign.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST007', 'Pet Paradise Store', 'Robert Anderson', NULL, '147 Birch Road, Boston, MA 02101', NULL, NULL, NULL, 'USA', '(555) 789-0123', NULL, 'robert@petparadise.com', 'www.petparadise.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST008', 'Local Bookshop', 'Jennifer Lee', NULL, '258 Spruce Street, Minneapolis, MN 55401', NULL, NULL, NULL, 'USA', '(555) 890-1234', NULL, 'jennifer@localbookshop.com', 'www.localbookshop.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST009', 'Fresh Market Grocery', 'Thomas Hardy', NULL, '369 Willow Way, Phoenix, AZ 85001', NULL, NULL, NULL, 'USA', '(555) 901-2345', NULL, 'thomas@freshmarket.com', 'www.freshmarket.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST010', 'Handcrafted Furniture', 'Patricia Davis', NULL, '741 Ash Street, Nashville, TN 37201', NULL, NULL, NULL, 'USA', '(555) 012-3456', NULL, 'patricia@handcrafted.com', 'www.handcrafted.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST011', 'Mind & Body Wellness Center', 'Sophia Patel', NULL, '852 Sage Circle, Boulder, CO 80301', NULL, NULL, NULL, 'USA', '(555) 234-5678', NULL, 'sophia@mindbodywellness.com', 'www.mindbodywellness.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST012', 'CrossFit Iron Warriors', 'Chris Murphy', NULL, '963 Warrior Way, Miami, FL 33101', NULL, NULL, NULL, 'USA', '(555) 345-6789', NULL, 'chris@ironwarriors.com', 'www.ironwarriors.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST013', 'Blooms & Bouquets', 'Rachel Green', NULL, '741 Rose Lane, Charleston, SC 29401', NULL, NULL, NULL, 'USA', '(555) 456-7890', NULL, 'rachel@bloomsandbouquets.com', 'www.bloomsandbouquets.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST014', 'Sunrise Diner', 'Marcus Williams', 'Owner', '102 Broad Street, Richmond, VA 23219', NULL, NULL, NULL, 'USA', '(804) 555-1201', NULL, 'marcus@sunrisediner.com', 'www.sunrisediner.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST015', 'Golden Scissors Salon', 'Aisha Jackson', 'Owner', '415 Market Street, Wilmington, DE 19801', NULL, NULL, NULL, 'USA', '(302) 555-1302', NULL, 'aisha@goldenscissors.com', 'www.goldenscissors.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST016', 'Precision Auto Repair', 'Tony Russo', 'Manager', '730 Industrial Blvd, Detroit, MI 48201', NULL, NULL, NULL, 'USA', '(313) 555-1403', NULL, 'tony@precisionauto.com', 'www.precisionauto.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST017', 'Parker & Associates Law', 'Diana Parker', 'Partner', '55 Court Square, Atlanta, GA 30303', NULL, NULL, NULL, 'USA', '(404) 555-1504', NULL, 'diana@parkerlaw.com', 'www.parkerlaw.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST018', 'Bright Smiles Dental', 'Dr. Kevin Nguyen', 'Director', '888 Health Plaza, Raleigh, NC 27601', NULL, NULL, NULL, 'USA', '(919) 555-1605', NULL, 'kevin@brightsmiles.com', 'www.brightsmilesdental.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST019', 'Hopstone Craft Brewery', 'Jake Morrison', 'Owner', '220 Brewery Lane, Portland, ME 04101', NULL, NULL, NULL, 'USA', '(207) 555-1706', NULL, 'jake@hopstonebrew.com', 'www.hopstonebrew.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST020', 'Tranquil Yoga Studio', 'Priya Sharma', 'Director', '91 Serenity Drive, Sedona, AZ 86336', NULL, NULL, NULL, 'USA', '(928) 555-1807', NULL, 'priya@tranquilyoga.com', 'www.tranquilyoga.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST021', 'Pampered Paws Grooming', 'Brittany Cole', 'Owner', '345 Furry Friends Ave, Orlando, FL 32801', NULL, NULL, NULL, 'USA', '(407) 555-1908', NULL, 'brittany@pamperedpaws.com', 'www.pamperedpaws.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST022', 'QuickPrint Solutions', 'Raymond Kim', 'Manager', '678 Commerce Drive, Columbus, OH 43215', NULL, NULL, NULL, 'USA', '(614) 555-2009', NULL, 'raymond@quickprint.com', 'www.quickprintsolutions.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST023', 'Bright Minds Tutoring', 'Sandra Okafor', 'Director', '112 Scholar Lane, Ann Arbor, MI 48104', NULL, NULL, NULL, 'USA', '(734) 555-2110', NULL, 'sandra@brightminds.com', 'www.brightmindstutoring.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST024', 'Reliable Plumbing Co', 'Frank Kowalski', 'Owner', '900 Pipe Road, Milwaukee, WI 53202', NULL, NULL, NULL, 'USA', '(414) 555-2211', NULL, 'frank@reliableplumbing.com', 'www.reliableplumbingco.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST025', 'Sparks Electric Service', 'DeShawn Harris', 'Owner', '234 Volt Avenue, Memphis, TN 38103', NULL, NULL, NULL, 'USA', '(901) 555-2312', NULL, 'deshawn@sparkselectric.com', 'www.sparkselectric.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST026', 'Evergreen Landscaping', 'Maria Gonzalez', 'President', '567 Garden Path, Sacramento, CA 95814', NULL, NULL, NULL, 'USA', '(916) 555-2413', NULL, 'maria@evergreenland.com', 'www.evergreenlandscaping.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST027', 'Savory Bites Catering', 'Claudia Reyes', 'Owner', '430 Culinary Court, San Antonio, TX 78205', NULL, NULL, NULL, 'USA', '(210) 555-2514', NULL, 'claudia@savorybites.com', 'www.savorybitescatering.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST028', 'Shutter Studio Photography', 'Andre Baptiste', 'Owner', '88 Lens Lane, New Orleans, LA 70112', NULL, NULL, NULL, 'USA', '(504) 555-2615', NULL, 'andre@shutterstudio.com', 'www.shutterstudio.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST029', 'Pawsitive Vet Clinic', 'Dr. Emily Watson', 'Director', '321 Animal Care Blvd, Knoxville, TN 37902', NULL, NULL, NULL, 'USA', '(865) 555-2716', NULL, 'emily@pawsitivevet.com', 'www.pawsitivevet.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST030', 'Dragon''s Den Martial Arts', 'Hiroshi Tanaka', 'Owner', '155 Dojo Street, Honolulu, HI 96813', NULL, NULL, NULL, 'USA', '(808) 555-2817', NULL, 'hiroshi@dragonsden.com', 'www.dragonsdenma.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST031', 'Graceful Steps Dance Studio', 'Natasha Volkov', 'Director', '740 Ballet Avenue, Pittsburgh, PA 15222', NULL, NULL, NULL, 'USA', '(412) 555-2918', NULL, 'natasha@gracefulsteps.com', 'www.gracefulstepsdance.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST032', 'Harmony Music School', 'Carlos Medina', 'Director', '29 Melody Lane, Santa Fe, NM 87501', NULL, NULL, NULL, 'USA', '(505) 555-3019', NULL, 'carlos@harmonymusic.com', 'www.harmonymusicschool.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST033', 'Ace Hardware & Home', 'Bill Turner', 'Manager', '611 Tool Road, Boise, ID 83702', NULL, NULL, NULL, 'USA', '(208) 555-3120', NULL, 'bill@acehardwarehome.com', 'www.acehardwarehome.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST034', 'Spin Cycle Laundromat', 'Yolanda Foster', 'Owner', '870 Wash Street, Baltimore, MD 21201', NULL, NULL, NULL, 'USA', '(410) 555-3221', NULL, 'yolanda@spincycle.com', 'www.spincyclelaundry.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST035', 'Pristine Dry Cleaners', 'Jin Park', 'Owner', '445 Press Lane, Philadelphia, PA 19103', NULL, NULL, NULL, 'USA', '(215) 555-3322', NULL, 'jin@pristineclean.com', 'www.pristinecleaners.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST036', 'Summit Tax Services', 'Gerald Washington', 'President', '33 Fiscal Drive, Charlotte, NC 28202', NULL, NULL, NULL, 'USA', '(704) 555-3423', NULL, 'gerald@summittax.com', 'www.summittaxservices.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST037', 'Shield Insurance Agency', 'Karen O''Brien', 'Owner', '512 Policy Blvd, Indianapolis, IN 46204', NULL, NULL, NULL, 'USA', '(317) 555-3524', NULL, 'karen@shieldinsurance.com', 'www.shieldinsurance.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST038', 'Keystone Real Estate', 'Victor Delgado', 'Broker', '77 Realty Row, Scottsdale, AZ 85251', NULL, NULL, NULL, 'USA', '(480) 555-3625', NULL, 'victor@keystonere.com', 'www.keystonerealestate.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST039', 'Aligned Chiropractic', 'Dr. Susan Meyer', 'Director', '210 Spine Way, Madison, WI 53703', NULL, NULL, NULL, 'USA', '(608) 555-3726', NULL, 'susan@alignedchiro.com', 'www.alignedchiropractic.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST040', 'ClearView Optometry', 'Dr. Alan Pham', 'Director', '368 Vision Plaza, Tampa, FL 33602', NULL, NULL, NULL, 'USA', '(813) 555-3827', NULL, 'alan@clearvieweye.com', 'www.clearviewoptometry.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST041', 'Rustic Table Restaurant', 'Nicole Freeman', 'Owner', '425 Dining Drive, Savannah, GA 31401', NULL, NULL, NULL, 'USA', '(912) 555-3928', NULL, 'nicole@rustictable.com', 'www.rustictable.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST042', 'Crossroads Auto Body', 'Miguel Santos', 'Manager', '810 Body Shop Lane, El Paso, TX 79901', NULL, NULL, NULL, 'USA', '(915) 555-4029', NULL, 'miguel@crossroadsauto.com', 'www.crossroadsautobody.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST043', 'Stonewall Masonry', 'Patrick O''Malley', 'Owner', '135 Mason Court, Hartford, CT 06103', NULL, NULL, NULL, 'USA', '(860) 555-4130', NULL, 'patrick@stonewallmasonry.com', 'www.stonewallmasonry.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST044', 'Pixel Perfect Web Design', 'Jasmine Howard', 'Director', '290 Digital Drive, Raleigh, NC 27601', NULL, NULL, NULL, 'USA', '(919) 555-4231', NULL, 'jasmine@pixelperfect.com', 'www.pixelperfectweb.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST045', 'Blue Ridge Roofing', 'Travis Campbell', 'Owner', '604 Shingle Street, Asheville, NC 28801', NULL, NULL, NULL, 'USA', '(828) 555-4332', NULL, 'travis@blueridgeroofing.com', 'www.blueridgeroofing.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST046', 'Oceanside Surf Shop', 'Kai Nakamura', 'Owner', '18 Beach Boulevard, San Diego, CA 92101', NULL, NULL, NULL, 'USA', '(619) 555-4433', NULL, 'kai@oceansidesurf.com', 'www.oceansidesurfshop.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST047', 'Mountain View Dental', 'Dr. Rebecca Stone', 'Director', '503 Summit Road, Salt Lake City, UT 84101', NULL, NULL, NULL, 'USA', '(801) 555-4534', NULL, 'rebecca@mountainviewdent.com', 'www.mountainviewdental.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST048', 'Cornerstone Accounting', 'Helen Chang', 'President', '247 Ledger Lane, San Jose, CA 95113', NULL, NULL, NULL, 'USA', '(408) 555-4635', NULL, 'helen@cornerstoneacct.com', 'www.cornerstoneacct.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST049', 'Lucky Paws Pet Sitting', 'Tanya Brooks', 'Owner', '680 Critter Court, Tucson, AZ 85701', NULL, NULL, NULL, 'USA', '(520) 555-4736', NULL, 'tanya@luckypaws.com', 'www.luckypawspetsitting.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST050', 'Iron Horse Welding', 'Dmitri Volkov', 'Owner', '915 Forge Road, Tulsa, OK 74103', NULL, NULL, NULL, 'USA', '(918) 555-4837', NULL, 'dmitri@ironhorseweld.com', 'www.ironhorsewelding.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST051', 'Heartland Veterinary', 'Dr. Laura Mitchell', 'Director', '340 Paw Print Lane, Des Moines, IA 50309', NULL, NULL, NULL, 'USA', '(515) 555-4938', NULL, 'laura@heartlandvet.com', 'www.heartlandvet.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST052', 'Redwood Construction', 'Steven Grant', 'President', '762 Builder Blvd, Eugene, OR 97401', NULL, NULL, NULL, 'USA', '(541) 555-5039', NULL, 'steven@redwoodconst.com', 'www.redwoodconstruction.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST053', 'Bella Notte Italian Bistro', 'Giovanni Lombardi', 'Owner', '410 Trattoria Way, Providence, RI 02903', NULL, NULL, NULL, 'USA', '(401) 555-5140', NULL, 'giovanni@bellanotte.com', 'www.bellanotteristorante.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST054', 'Harbor View Realty', 'Christine Palmer', 'Broker', '55 Harbor Drive, Annapolis, MD 21401', NULL, NULL, NULL, 'USA', '(410) 555-5241', NULL, 'christine@harborview.com', 'www.harborviewrealty.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST055', 'Peak Performance Fitness', 'Derek Robinson', 'Manager', '820 Gym Road, Colorado Springs, CO 80903', NULL, NULL, NULL, 'USA', '(719) 555-5342', NULL, 'derek@peakperformance.com', 'www.peakperformfit.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST056', 'Jade Garden Restaurant', 'Wei Lin', 'Owner', '133 Dragon Street, San Francisco, CA 94108', NULL, NULL, NULL, 'USA', '(415) 555-5443', NULL, 'wei@jadegarden.com', 'www.jadegardenrest.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST057', 'Sunrise Bakery & Cafe', 'Fatima Al-Rashid', 'Owner', '207 Morning Glory Ave, Dearborn, MI 48124', NULL, NULL, NULL, 'USA', '(313) 555-5544', NULL, 'fatima@sunrisebakery.com', 'www.sunrisebakerycafe.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST058', 'Liberty Tax Pros', 'Harold Jenkins', 'Director', '490 Freedom Blvd, Omaha, NE 68102', NULL, NULL, NULL, 'USA', '(402) 555-5645', NULL, 'harold@libertytaxpros.com', 'www.libertytaxpros.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST059', 'Timber Wolf Construction', 'Erik Johansson', 'President', '305 Lumber Lane, Duluth, MN 55802', NULL, NULL, NULL, 'USA', '(218) 555-5746', NULL, 'erik@timberwolfconst.com', 'www.timberwolfconst.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST060', 'Silver Creek Jewelry', 'Amara Osei', 'Owner', '172 Gem Court, Albuquerque, NM 87102', NULL, NULL, NULL, 'USA', '(505) 555-5847', NULL, 'amara@silvercreek.com', 'www.silvercreekjewelry.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST061', 'Main Street Pharmacy', 'Dr. Richard Huang', 'Director', '501 Rx Road, Lancaster, PA 17603', NULL, NULL, NULL, 'USA', '(717) 555-5948', NULL, 'richard@mainstreetpharm.com', 'www.mainstreetpharmacy.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST062', 'Coastal Kayak Adventures', 'Samantha Reed', 'Owner', '82 Paddle Path, Charleston, SC 29401', NULL, NULL, NULL, 'USA', '(843) 555-6049', NULL, 'samantha@coastalkayak.com', 'www.coastalkayak.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST063', 'Precision CNC Machining', 'Roy Fitzgerald', 'President', '640 Factory Drive, Wichita, KS 67202', NULL, NULL, NULL, 'USA', '(316) 555-6150', NULL, 'roy@precisioncnc.com', 'www.precisioncnc.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST064', 'Maple Street Deli', 'Deborah Klein', 'Owner', '310 Maple Street, Burlington, VT 05401', NULL, NULL, NULL, 'USA', '(802) 555-6251', NULL, 'deborah@maplestreetdeli.com', 'www.maplestreetdeli.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST065', 'Lone Star Pest Control', 'Hector Ramirez', 'Owner', '425 Critter Way, Dallas, TX 75201', NULL, NULL, NULL, 'USA', '(214) 555-6352', NULL, 'hector@lonestarpest.com', 'www.lonestarpestcontrol.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST066', 'Cascade Window Cleaning', 'Nathan Blake', 'Owner', '190 Clear View Lane, Tacoma, WA 98402', NULL, NULL, NULL, 'USA', '(253) 555-6453', NULL, 'nathan@cascadewindow.com', 'www.cascadewindowclean.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST067', 'Red Barn Antiques', 'Dorothy Sullivan', 'Owner', '715 Heritage Road, Lexington, KY 40507', NULL, NULL, NULL, 'USA', '(859) 555-6554', NULL, 'dorothy@redbarnantiques.com', 'www.redbarnantiques.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST068', 'Summit Physical Therapy', 'Dr. Angela Cruz', 'Director', '280 Recovery Blvd, Denver, CO 80202', NULL, NULL, NULL, 'USA', '(303) 555-6655', NULL, 'angela@summitpt.com', 'www.summitphysicaltherapy.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST069', 'Firefly Event Planning', 'Megan Stewart', 'Owner', '44 Celebration Lane, Nashville, TN 37203', NULL, NULL, NULL, 'USA', '(615) 555-6756', NULL, 'megan@fireflyevents.com', 'www.fireflyevents.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST070', 'Copper Kettle Brewpub', 'Sean Gallagher', 'Owner', '330 Malt Avenue, Asheville, NC 28801', NULL, NULL, NULL, 'USA', '(828) 555-6857', NULL, 'sean@copperkettle.com', 'www.copperkettlebrewpub.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST071', 'Heritage Woodworking', 'Douglas Warren', 'Owner', '580 Timber Trail, Missoula, MT 59801', NULL, NULL, NULL, 'USA', '(406) 555-6958', NULL, 'douglas@heritagewood.com', 'www.heritagewoodworking.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST072', 'Blossom Hill Florist', 'Yuki Yamamoto', 'Owner', '93 Petal Place, Portland, OR 97205', NULL, NULL, NULL, 'USA', '(503) 555-7059', NULL, 'yuki@blossomhill.com', 'www.blossomhillflorist.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST073', 'Lakeshore Dental Care', 'Dr. Brian Foster', 'Director', '201 Smile Drive, Cleveland, OH 44113', NULL, NULL, NULL, 'USA', '(216) 555-7160', NULL, 'brian@lakeshoredental.com', 'www.lakeshoredental.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST074', 'Trailhead Outdoor Gear', 'Amanda Larson', 'Manager', '415 Adventure Blvd, Bend, OR 97701', NULL, NULL, NULL, 'USA', '(541) 555-7261', NULL, 'amanda@trailheadgear.com', 'www.trailheadgear.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST075', 'Golden Gate Accounting', 'Philip Tran', 'President', '660 Financial Way, Oakland, CA 94612', NULL, NULL, NULL, 'USA', '(510) 555-7362', NULL, 'philip@goldengatecpa.com', 'www.goldengateaccounting.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST076', 'Magnolia Insurance Group', 'Sharon Whitfield', 'Director', '118 Coverage Court, Jackson, MS 39201', NULL, NULL, NULL, 'USA', '(601) 555-7463', NULL, 'sharon@magnoliainsure.com', 'www.magnoliainsurance.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST077', 'Prairie Wind Farm Supply', 'Kenneth Olson', 'Owner', '840 Harvest Road, Sioux Falls, SD 57104', NULL, NULL, NULL, 'USA', '(605) 555-7564', NULL, 'kenneth@prairiewind.com', 'www.prairiewindfarm.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST078', 'Sapphire Nail Spa', 'Thi Nguyen', 'Owner', '275 Beauty Boulevard, Houston, TX 77002', NULL, NULL, NULL, 'USA', '(713) 555-7665', NULL, 'thi@sapphirenails.com', 'www.sapphirenailspa.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST079', 'Canyon View Realty', 'Lawrence Begay', 'Broker', '430 Mesa Drive, Flagstaff, AZ 86001', NULL, NULL, NULL, 'USA', '(928) 555-7766', NULL, 'lawrence@canyonviewre.com', 'www.canyonviewrealty.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST080', 'Olympus Martial Arts', 'Stavros Papadopoulos', 'Director', '156 Warrior Way, Tampa, FL 33607', NULL, NULL, NULL, 'USA', '(813) 555-7867', NULL, 'stavros@olympusma.com', 'www.olympusmartialarts.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST081', 'Mosaic Tile & Stone', 'Rosa Gutierrez', 'Owner', '722 Artisan Way, Santa Barbara, CA 93101', NULL, NULL, NULL, 'USA', '(805) 555-7968', NULL, 'rosa@mosaictile.com', 'www.mosaictileandstone.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST082', 'Northstar IT Consulting', 'Rajesh Kapoor', 'President', '335 Tech Park Drive, Minneapolis, MN 55403', NULL, NULL, NULL, 'USA', '(612) 555-8069', NULL, 'rajesh@northstarit.com', 'www.northstarit.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST083', 'Harbor Seafood Market', 'Liam O''Connor', 'Manager', '60 Wharf Street, Gloucester, MA 01930', NULL, NULL, NULL, 'USA', '(978) 555-8170', NULL, 'liam@harborseafood.com', 'www.harborseafoodmarket.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST084', 'Peach State Plumbing', 'Jerome Adams', 'Owner', '490 Pipeline Road, Macon, GA 31201', NULL, NULL, NULL, 'USA', '(478) 555-8271', NULL, 'jerome@peachstateplumb.com', 'www.peachstateplumbing.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST085', 'Desert Rose Spa', 'Leila Hashemi', 'Owner', '105 Oasis Drive, Scottsdale, AZ 85254', NULL, NULL, NULL, 'USA', '(480) 555-8372', NULL, 'leila@desertrosespa.com', 'www.desertrosespa.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST086', 'Capitol City Printing', 'Wayne Henderson', 'Manager', '810 Press Court, Austin, TX 78702', NULL, NULL, NULL, 'USA', '(512) 555-8473', NULL, 'wayne@capitolprint.com', 'www.capitolcityprinting.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST087', 'Green Valley Nursery', 'Connie Yamada', 'Owner', '230 Greenhouse Lane, Fresno, CA 93721', NULL, NULL, NULL, 'USA', '(559) 555-8574', NULL, 'connie@greenvalley.com', 'www.greenvalleynursery.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST088', 'Bayou Cajun Kitchen', 'Antoine Dupree', 'Owner', '555 Bayou Road, Baton Rouge, LA 70801', NULL, NULL, NULL, 'USA', '(225) 555-8675', NULL, 'antoine@bayoucajun.com', 'www.bayoucajunkitchen.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST089', 'Pinnacle Roofing Co', 'Gregory Nash', 'President', '340 Ridgeline Drive, Little Rock, AR 72201', NULL, NULL, NULL, 'USA', '(501) 555-8776', NULL, 'gregory@pinnacleroofing.com', 'www.pinnacleroofing.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST090', 'Starlight Dance Academy', 'Isabella Moretti', 'Director', '75 Twirl Avenue, Kansas City, MO 64106', NULL, NULL, NULL, 'USA', '(816) 555-8877', NULL, 'isabella@starlightdance.com', 'www.starlightdance.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST091', 'Frontier Fence Company', 'Russell Hayes', 'Owner', '620 Post Road, Cheyenne, WY 82001', NULL, NULL, NULL, 'USA', '(307) 555-8978', NULL, 'russell@frontierfence.com', 'www.frontierfence.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST092', 'Clarity Eye Care', 'Dr. Naomi Sato', 'Director', '148 Optical Lane, Bellevue, WA 98004', NULL, NULL, NULL, 'USA', '(425) 555-9079', NULL, 'naomi@clarityeye.com', 'www.clarityeyecare.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST093', 'Crescent Moon Bakery', 'Omar Hassan', 'Owner', '215 Pastry Lane, Dearborn, MI 48126', NULL, NULL, NULL, 'USA', '(313) 555-9180', NULL, 'omar@crescentmoon.com', 'www.crescentmoonbakery.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST094', 'Blue Heron Photography', 'Keiko Watanabe', 'Owner', '390 Shutter Street, Savannah, GA 31401', NULL, NULL, NULL, 'USA', '(912) 555-9281', NULL, 'keiko@blueheronphoto.com', 'www.blueheronphoto.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST095', 'Midtown Music Academy', 'Terrence Jackson', 'Director', '505 Melody Way, Atlanta, GA 30308', NULL, NULL, NULL, 'USA', '(404) 555-9382', NULL, 'terrence@midtownmusic.com', 'www.midtownmusicacademy.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST096', 'Elm Street Chiropractic', 'Dr. Kathryn Burke', 'Director', '122 Elm Street, Springfield, IL 62701', NULL, NULL, NULL, 'USA', '(217) 555-9483', NULL, 'kathryn@elmstreetchiro.com', 'www.elmstreetchiro.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST097', 'Pioneer Moving Company', 'Andrei Petrov', 'Manager', '830 Hauler Highway, Oklahoma City, OK 73102', NULL, NULL, NULL, 'USA', '(405) 555-9584', NULL, 'andrei@pioneermoving.com', 'www.pioneermoving.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST098', 'Wildflower Boutique', 'Melissa Herrera', 'Owner', '47 Fashion Lane, Taos, NM 87571', NULL, NULL, NULL, 'USA', '(575) 555-9685', NULL, 'melissa@wildflowershop.com', 'www.wildflowerboutique.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST099', 'Granite Countertops Plus', 'Roberto Marquez', 'Owner', '690 Stone Way, Las Vegas, NV 89101', NULL, NULL, NULL, 'USA', '(702) 555-9786', NULL, 'roberto@granitecounters.com', 'www.granitecountersplus.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST100', 'Birchwood Family Medicine', 'Dr. Pamela Rhodes', 'Director', '210 Wellness Blvd, Portland, ME 04101', NULL, NULL, NULL, 'USA', '(207) 555-9887', NULL, 'pamela@birchwoodmed.com', 'www.birchwoodfamilymed.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST101', 'Riverbend Coffee Roasters', 'Jamal Washington', 'Owner', '330 Roast Road, Louisville, KY 40202', NULL, NULL, NULL, 'USA', '(502) 555-1001', NULL, 'jamal@riverbendcoffee.com', 'www.riverbendcoffee.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST102', 'Cactus Bloom Landscaping', 'Elena Vargas', 'Owner', '475 Desert View Drive, Tucson, AZ 85702', NULL, NULL, NULL, 'USA', '(520) 555-1102', NULL, 'elena@cactusbloom.com', 'www.cactusbloomlandscape.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST103', 'Northern Lights Electric', 'Henrik Lindqvist', 'Owner', '88 Aurora Lane, Anchorage, AK 99501', NULL, NULL, NULL, 'USA', '(907) 555-1203', NULL, 'henrik@northernlights.com', 'www.northernlightselectric.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST104', 'Magnolia Bridal Boutique', 'Danielle Baptiste', 'Owner', '160 Wedding Way, Savannah, GA 31405', NULL, NULL, NULL, 'USA', '(912) 555-1304', NULL, 'danielle@magnoliabridal.com', 'www.magnoliabridal.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST105', 'Summit Legal Services', 'Theodore Kim', 'Partner', '720 Justice Plaza, Denver, CO 80204', NULL, NULL, NULL, 'USA', '(303) 555-1405', NULL, 'theodore@summitlegal.com', 'www.summitlegalservices.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST106', 'Pineapple Express Smoothies', 'Aaliyah Morris', 'Owner', '55 Tropical Ave, Fort Lauderdale, FL 33301', NULL, NULL, NULL, 'USA', '(954) 555-1506', NULL, 'aaliyah@pineappleexpress.com', 'www.pineapplexpress.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST107', 'Heartland HVAC Services', 'Dale Swenson', 'Owner', '415 Climate Court, Topeka, KS 66603', NULL, NULL, NULL, 'USA', '(785) 555-1607', NULL, 'dale@heartlandhvac.com', 'www.heartlandhvac.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST108', 'Serenity Day Spa', 'Monique Beaumont', 'Owner', '230 Relaxation Road, Napa, CA 94559', NULL, NULL, NULL, 'USA', '(707) 555-1708', NULL, 'monique@serenitydayspa.com', 'www.serenitydayspa.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST109', 'Dogwood Veterinary Care', 'Dr. Charles Bennett', 'Director', '340 Animal Care Way, Birmingham, AL 35203', NULL, NULL, NULL, 'USA', '(205) 555-1809', NULL, 'charles@dogwoodvet.com', 'www.dogwoodvetcare.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST110', 'Redstone Pizza Kitchen', 'Salvatore DiNapoli', 'Owner', '180 Brick Oven Lane, Newark, NJ 07102', NULL, NULL, NULL, 'USA', '(973) 555-1910', NULL, 'sal@redstonepizza.com', 'www.redstonepizza.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST111', 'Pacific Rim Taekwondo', 'Sung-Ho Park', 'Director', '605 Martial Way, Tacoma, WA 98403', NULL, NULL, NULL, 'USA', '(253) 555-2011', NULL, 'sungho@pacificrimtkd.com', 'www.pacificrimtkd.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST112', 'Whitestone Dental Group', 'Dr. Meredith Clarke', 'Director', '92 Pearl Street, Stamford, CT 06901', NULL, NULL, NULL, 'USA', '(203) 555-2112', NULL, 'meredith@whitestonedental.com', 'www.whitestonedental.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST113', 'Cedar Creek Woodworks', 'Benjamin Carpenter', 'Owner', '470 Sawmill Road, Chattanooga, TN 37402', NULL, NULL, NULL, 'USA', '(423) 555-2213', NULL, 'benjamin@cedarcreekwood.com', 'www.cedarcreekwoodworks.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST114', 'Aloha Shaved Ice', 'Kalani Kealoha', 'Owner', '35 Hibiscus Lane, Kailua, HI 96734', NULL, NULL, NULL, 'USA', '(808) 555-2314', NULL, 'kalani@alohashavedice.com', 'www.alohashavedice.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST115', 'Appalachian Outfitters', 'Wayne Combs', 'Manager', '610 Mountain Trail, Boone, NC 28607', NULL, NULL, NULL, 'USA', '(828) 555-2415', NULL, 'wayne@appalachianout.com', 'www.appalachianoutfitters.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST116', 'Blue Sky Solar Energy', 'Anita Desai', 'President', '830 Sunbeam Drive, Albuquerque, NM 87106', NULL, NULL, NULL, 'USA', '(505) 555-2516', NULL, 'anita@blueskysolar.com', 'www.blueskysolar.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST117', 'Cobblestone Real Estate', 'Arthur Middleton', 'Broker', '155 Heritage Square, Alexandria, VA 22314', NULL, NULL, NULL, 'USA', '(703) 555-2617', NULL, 'arthur@cobblestonere.com', 'www.cobblestonerealty.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST118', 'Crimson Barber Shop', 'Marcus Brown', 'Owner', '42 Clipper Court, Birmingham, AL 35205', NULL, NULL, NULL, 'USA', '(205) 555-2718', NULL, 'marcus@crimsonbarber.com', 'www.crimsonbarbershop.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST119', 'Everest Cleaning Services', 'Suman Thapa', 'Owner', '720 Spotless Way, Fargo, ND 58102', NULL, NULL, NULL, 'USA', '(701) 555-2819', NULL, 'suman@everestcleaning.com', 'www.everestcleaning.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST120', 'Firebird Auto Detailing', 'Cesar Dominguez', 'Owner', '310 Shine Street, Albuquerque, NM 87104', NULL, NULL, NULL, 'USA', '(505) 555-2920', NULL, 'cesar@firebirdauto.com', 'www.firebirddetailing.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST121', 'Golden Harvest Farm Market', 'Loretta Whitfield', 'Owner', '580 Orchard Road, Lancaster, PA 17601', NULL, NULL, NULL, 'USA', '(717) 555-3021', NULL, 'loretta@goldenharvest.com', 'www.goldenharvestfarm.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST122', 'Hilltop Brewing Company', 'Patrick Brennan', 'Owner', '245 Brewery Hill, Burlington, VT 05401', NULL, NULL, NULL, 'USA', '(802) 555-3122', NULL, 'patrick@hilltopbrew.com', 'www.hilltopbrewing.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST123', 'Ivory Keys Piano Studio', 'Grace Kwon', 'Director', '110 Sonata Lane, Nashville, TN 37205', NULL, NULL, NULL, 'USA', '(615) 555-3223', NULL, 'grace@ivorykeys.com', 'www.ivorykeyspiano.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST124', 'Juniper Wellness Clinic', 'Dr. Rachel Goldberg', 'Director', '380 Healing Way, Boulder, CO 80302', NULL, NULL, NULL, 'USA', '(303) 555-3324', NULL, 'rachel@juniperwellness.com', 'www.juniperwellness.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST125', 'Keystone Pest Solutions', 'Martin Shelby', 'Manager', '690 Exterminator Ave, Harrisburg, PA 17101', NULL, NULL, NULL, 'USA', '(717) 555-3425', NULL, 'martin@keystonepest.com', 'www.keystonepest.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST126', 'Lakewood Animal Hospital', 'Dr. Sandra Ivanova', 'Director', '215 Pet Care Blvd, Lakewood, CO 80226', NULL, NULL, NULL, 'USA', '(303) 555-3526', NULL, 'sandra@lakewoodanimal.com', 'www.lakewoodanimal.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST127', 'Mesa Verde Tacos', 'Ricardo Fuentes', 'Owner', '440 Taco Trail, Mesa, AZ 85201', NULL, NULL, NULL, 'USA', '(480) 555-3627', NULL, 'ricardo@mesaverdetacos.com', 'www.mesaverdetacos.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST128', 'New Leaf Organic Market', 'Sierra Dawson', 'Manager', '88 Green Way, Eugene, OR 97403', NULL, NULL, NULL, 'USA', '(541) 555-3728', NULL, 'sierra@newleaforganic.com', 'www.newleaforganic.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST129', 'Oak Park Insurance', 'Stanley Kowalczyk', 'Director', '325 Coverage Lane, Oak Park, IL 60301', NULL, NULL, NULL, 'USA', '(708) 555-3829', NULL, 'stanley@oakparkinsure.com', 'www.oakparkinsurance.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST130', 'Peachtree Painting Co', 'Lamar Gibson', 'Owner', '560 Brush Street, Atlanta, GA 30312', NULL, NULL, NULL, 'USA', '(404) 555-3930', NULL, 'lamar@peachtreepainting.com', 'www.peachtreepainting.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST131', 'Quicksilver Bike Shop', 'Tyler Christiansen', 'Owner', '142 Spoke Lane, Portland, OR 97209', NULL, NULL, NULL, 'USA', '(503) 555-4031', NULL, 'tyler@quicksilverbikes.com', 'www.quicksilverbikes.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST132', 'Riverside Canoe Rental', 'Jolene Blackwater', 'Owner', '78 River Road, Fayetteville, AR 72701', NULL, NULL, NULL, 'USA', '(479) 555-4132', NULL, 'jolene@riversidecanoe.com', 'www.riversidecanoe.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST133', 'Sunflower Montessori', 'Hannah Johansson', 'Director', '450 Learning Lane, Lawrence, KS 66044', NULL, NULL, NULL, 'USA', '(785) 555-4233', NULL, 'hannah@sunflowerschool.com', 'www.sunflowermontessori.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST134', 'Thunderbird Glass Works', 'Manny Archuleta', 'Owner', '305 Kiln Court, Santa Fe, NM 87505', NULL, NULL, NULL, 'USA', '(505) 555-4334', NULL, 'manny@thunderbirdglass.com', 'www.thunderbirdglass.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST135', 'Unity Yoga & Pilates', 'Deepa Krishnan', 'Director', '220 Balance Blvd, Austin, TX 78704', NULL, NULL, NULL, 'USA', '(512) 555-4435', NULL, 'deepa@unityyoga.com', 'www.unityyogapilates.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST136', 'Valley Forge Ironworks', 'Ivan Petrov', 'Owner', '610 Anvil Road, Valley Forge, PA 19460', NULL, NULL, NULL, 'USA', '(610) 555-4536', NULL, 'ivan@valleyforgeironw.com', 'www.valleyforgeironworks.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST137', 'Windy City Dog Walkers', 'Crystal Simmons', 'Owner', '185 Paw Trail, Chicago, IL 60614', NULL, NULL, NULL, 'USA', '(312) 555-4637', NULL, 'crystal@windycitydogs.com', 'www.windycitydogwalkers.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST138', 'Yellowstone Fly Fishing', 'Garrett Caldwell', 'Owner', '430 Angler Avenue, Bozeman, MT 59715', NULL, NULL, NULL, 'USA', '(406) 555-4738', NULL, 'garrett@yellowstonefly.com', 'www.yellowstonefly.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST139', 'Zenith Acupuncture Clinic', 'Dr. Mei-Ling Chen', 'Director', '95 Harmony Path, San Francisco, CA 94115', NULL, NULL, NULL, 'USA', '(415) 555-4839', NULL, 'meiling@zenithacupunct.com', 'www.zenithacupuncture.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST140', 'Anchor Marine Services', 'Pete Henriksen', 'Owner', '20 Dock Street, Annapolis, MD 21403', NULL, NULL, NULL, 'USA', '(410) 555-4940', NULL, 'pete@anchormarine.com', 'www.anchormarineservices.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST141', 'Buckeye Barbecue Pit', 'Dwayne Miller', 'Owner', '335 Smoker Lane, Columbus, OH 43201', NULL, NULL, NULL, 'USA', '(614) 555-5041', NULL, 'dwayne@buckeyebbq.com', 'www.buckeyebbq.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST142', 'Catalina Swim School', 'Lucia Navarro', 'Director', '180 Pool Lane, Long Beach, CA 90802', NULL, NULL, NULL, 'USA', '(562) 555-5142', NULL, 'lucia@catalinaswim.com', 'www.catalinaswimschool.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST143', 'Delta Appliance Repair', 'Vernon Clay', 'Owner', '525 Fix-It Blvd, Jackson, MS 39202', NULL, NULL, NULL, 'USA', '(601) 555-5243', NULL, 'vernon@deltaappliance.com', 'www.deltaappliancerepair.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST144', 'Emerald Isle Pub', 'Declan Murphy', 'Owner', '60 Shamrock Street, Boston, MA 02116', NULL, NULL, NULL, 'USA', '(617) 555-5344', NULL, 'declan@emeraldislepub.com', 'www.emeraldislepub.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST145', 'Foxglove Herbal Apothecary', 'Iris Greenleaf', 'Owner', '310 Botanical Way, Ashland, OR 97520', NULL, NULL, NULL, 'USA', '(541) 555-5445', NULL, 'iris@foxgloveherbal.com', 'www.foxgloveherbal.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST146', 'Great Basin Heating', 'Norman Walsh', 'Owner', '720 Furnace Road, Reno, NV 89501', NULL, NULL, NULL, 'USA', '(775) 555-5546', NULL, 'norman@greatbasinhtg.com', 'www.greatbasinheating.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST147', 'Hawkeye Security Systems', 'Janet Kowalski', 'President', '410 Sentry Drive, Cedar Rapids, IA 52401', NULL, NULL, NULL, 'USA', '(319) 555-5647', NULL, 'janet@hawkeyesecurity.com', 'www.hawkeyesecurity.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST148', 'Indigo Tattoo Studio', 'Raven Blackbird', 'Owner', '88 Ink Avenue, Austin, TX 78703', NULL, NULL, NULL, 'USA', '(512) 555-5748', NULL, 'raven@indigotattoo.com', 'www.indigotattoostudio.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST149', 'Jupiter Gymnastics Club', 'Olga Federova', 'Director', '240 Tumble Way, Jupiter, FL 33458', NULL, NULL, NULL, 'USA', '(561) 555-5849', NULL, 'olga@jupitergymnastics.com', 'www.jupitergymnastics.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST150', 'Knotty Pine Cabin Rentals', 'Chester Brogan', 'Manager', '15 Pinecone Trail, Gatlinburg, TN 37738', NULL, NULL, NULL, 'USA', '(865) 555-5950', NULL, 'chester@knottypine.com', 'www.knottypinecabins.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- =====================================================
-- CRM Data: Customer Notes
-- =====================================================
INSERT INTO customer_note (customer_id, note_text, created_at, updated_at) VALUES
('CUST001', 'Initial meeting went well. Sarah is interested in expanding her coffee shop chain and needs ergonomic furniture and equipment for her new locations.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST001', 'Follow-up call scheduled for next week to discuss bulk pricing on standing desks and ergonomic chairs.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST001', 'Sarah mentioned they are opening a second location in the Pearl District. Great opportunity for increased orders.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST002', 'Michael is looking for durable outdoor-rated office furniture for his garden center. Needs weather-resistant options for the customer consultation area.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST002', 'Sent product catalog and pricing sheet. Awaiting response on preferred items.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST003', 'Tech Solutions IT is building an Imagination Pod on the 4th floor — Interstellar Ops Center theme with holographic displays and an ambient star field ceiling.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST003', 'Contract signed for the Interstellar Ops Center build-out. David Rodriguez approved the premium holographic package; construction is underway with a target handoff by end of Q2.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST004', 'Emma is interested in upgrading her bakery''s back-office setup. Needs a compact desk, shelving, and a POS workstation.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST005', 'James wants to create a comfortable lounge area in his fitness studio for members. Needs durable seating and coffee table options.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST005', 'Sent product catalog with commercial-grade options. James approved the lounge furniture package for his studio.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST006', 'Creative Design Co outfitted their new open-plan studio with our modular desks. Very positive feedback. Potential for additional orders as they hire.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST007', 'Robert inquired about durable reception furniture for his pet store. Needs scratch-resistant seating for the customer waiting area.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST008', 'Jennifer wants comfortable reading chairs and modular shelving for her bookshop''s author reading area. Planning to expand the event space.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST009', 'Fresh Market Grocery interested in upgrading their break room with new tables, chairs, and storage cabinets.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST009', 'Retail partnership agreement drafted. Awaiting legal review from both sides.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST010', 'Patricia wants to refresh the office area of their furniture showroom with modern desks and conference room equipment.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST010', 'Office area refresh was a huge success. Patricia requested a quote for outfitting their event space with flexible seating and display tables.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST014', 'Marcus is interested in new booths, tables, and a host station for Sunrise Diner. Current furniture is showing wear.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST019', 'Jake at Hopstone Brewery wants bar-height tables and stools for their new tasting room expansion.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST019', 'First delivery of tasting room furniture scheduled for next month. Outfitting space for 75 seats.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- =====================================================
-- CRM Data: Customer Contacts
-- =====================================================
INSERT INTO customer_contact (customer_id, first_name, last_name, email, title, phone, notes, created_at, updated_at) VALUES
('CUST001', 'Sarah', 'Johnson', 'sarah@brewandbean.com', 'Owner', '(555) 123-4567', 'Primary decision maker', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST001', 'Mike', 'Johnson', 'mike@brewandbean.com', 'Operations Manager', '(555) 123-4568', 'Handles day-to-day ordering and logistics', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST002', 'Michael', 'Chen', 'michael@greenthumb.com', 'Owner', '(555) 234-5678', 'Primary contact', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST002', 'Linda', 'Chen', 'linda@greenthumb.com', 'Events Coordinator', '(555) 234-5679', 'Manages garden events and furniture procurement', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST003', 'David', 'Rodriguez', 'david@techsolutions.com', 'CEO', '(555) 345-6789', 'Executive sponsor for office furniture contract', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST003', 'Amanda', 'Wong', 'amanda@techsolutions.com', 'Office Manager', '(555) 345-6790', 'Day-to-day office supplies contact. Handles equipment orders and deliveries.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST003', 'Kevin', 'Brooks', 'kevin@techsolutions.com', 'HR Director', '(555) 345-6791', 'Approves employee perks budget', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST004', 'Emma', 'Wilson', 'emma@sweettreats.com', 'Owner', '(555) 456-7890', 'Primary contact for co-branding discussions', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST005', 'James', 'Thompson', 'james@urbanfitness.com', 'Owner', '(555) 567-8901', 'Fitness nutrition focused', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST005', 'Carla', 'Diaz', 'carla@urbanfitness.com', 'Nutrition Coach', '(555) 567-8902', 'Reviews furniture options for ergonomic compliance', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST006', 'Lisa', 'Martinez', 'lisa@creativedesign.com', 'Owner', '(555) 678-9012', NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST007', 'Robert', 'Anderson', 'robert@petparadise.com', 'Owner', '(555) 789-0123', 'Hosts monthly pet adoption events', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST009', 'Thomas', 'Hardy', 'thomas@freshmarket.com', 'Owner', '(555) 901-2345', 'Decision maker for retail partnerships', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST009', 'Grace', 'Hardy', 'grace@freshmarket.com', 'Purchasing Manager', '(555) 901-2346', 'Handles product placement and inventory orders', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST010', 'Patricia', 'Davis', 'patricia@handcrafted.com', 'Owner', '(555) 012-3456', 'Hosts quarterly showroom events', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- =====================================================
-- CRM Data: Sales Person Assignments
-- =====================================================
INSERT INTO sales_person (customer_id, first_name, last_name, email, phone, territory, created_at, updated_at) VALUES
('CUST001', 'Sally', 'Sellers', 'sally.sellers@fantaco.com', '(555) 700-1001', 'Pacific Northwest', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST002', 'Sally', 'Sellers', 'sally.sellers@fantaco.com', '(555) 700-1001', 'Pacific Northwest', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST003', 'Sally', 'Sellers', 'sally.sellers@fantaco.com', '(555) 700-1001', 'Pacific Northwest', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST004', 'Jordan', 'Blake', 'jordan.blake@fantaco.com', '(555) 700-1002', 'Mountain West', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST005', 'Samantha', 'Cruz', 'samantha.cruz@fantaco.com', '(555) 700-1003', 'Texas & South Central', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST006', 'Jordan', 'Blake', 'jordan.blake@fantaco.com', '(555) 700-1002', 'Mountain West', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST007', 'Tanya', 'Patel', 'tanya.patel@fantaco.com', '(555) 700-1004', 'Northeast', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST008', 'Tanya', 'Patel', 'tanya.patel@fantaco.com', '(555) 700-1004', 'Northeast', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST009', 'Marcus', 'Fleming', 'marcus.fleming@fantaco.com', '(555) 700-1005', 'Southwest', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST010', 'Marcus', 'Fleming', 'marcus.fleming@fantaco.com', '(555) 700-1005', 'Southwest', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- =====================================================
-- Imagination Pod Projects
-- =====================================================
INSERT INTO project (customer_id, project_name, description, pod_theme, status, site_address, estimated_start_date, estimated_end_date, actual_start_date, actual_end_date, estimated_budget, actual_cost, created_at, updated_at) VALUES
('CUST003', 'Tech Solutions IT — Interstellar Ops Center', 'Transform 4th floor into an immersive interstellar command center with holographic displays and ambient star field ceiling.', 'INTERSTELLAR_SPACESHIP', 'IN_PROGRESS', '789 Pine Street, 4th Floor, San Francisco, CA 94101', '2026-03-01', '2026-06-30', '2026-03-05', NULL, 245000.00, 87500.00, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST006', 'Creative Design Co — Speakeasy Studio', 'Convert Suite 200 into a 1920s speakeasy-themed creative studio with password entry and vintage decor.', 'SPEAKEASY_1920S', 'PROPOSAL', '987 Cedar Lane, Suite 200, Chicago, IL 60601', '2026-07-01', '2026-09-30', NULL, NULL, 175000.00, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST010', 'Handcrafted Furniture — Zen Showroom', 'Build a serene zen garden showroom with bonsai, water features, and meditation nooks for client presentations.', 'ZEN_GARDEN', 'COMPLETED', '741 Ash Street, Building B, Nashville, TN 37201', '2026-01-15', '2026-03-15', '2026-01-20', '2026-03-10', 198000.00, 210500.00, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST001', 'Brew & Bean — Enchanted Forest Lounge', 'Create an enchanted forest-themed customer lounge with miniature waterfall, nature soundscapes, and living wall.', 'ENCHANTED_FOREST', 'APPROVED', '123 Main Street, 2nd Floor, Portland, OR 97201', '2026-05-01', '2026-07-31', NULL, NULL, 162000.00, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('CUST011', 'Mind & Body Wellness — Custom Meditation Suite', 'Design a custom meditation and wellness pod with adjustable lighting, sound therapy, and aromatherapy systems.', 'CUSTOM', 'IN_PROGRESS', '852 Sage Circle, Unit 3, Boulder, CO 80301', '2026-02-15', '2026-05-31', '2026-02-20', NULL, 135000.00, 62000.00, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- =====================================================
-- Project Milestones (5 per project, standard construction phases)
-- =====================================================

-- Project 1: Tech Solutions IT — Interstellar Ops Center (IN_PROGRESS)
INSERT INTO project_milestone (project_id, name, status, due_date, completed_date, notes, sort_order, created_at, updated_at) VALUES
(1, 'Site Assessment & Measurements', 'COMPLETED', '2026-03-08', '2026-03-07', 'Structural survey complete. Ceiling height adequate for star field installation.', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(1, 'Theme Design & Customer Approval', 'COMPLETED', '2026-03-22', '2026-03-20', 'Holographic display layout approved. Customer selected premium star field package.', 2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(1, 'Construction & Structural Work', 'IN_PROGRESS', '2026-04-30', NULL, 'Electrical upgrades 60% complete. Sound-dampening walls installed.', 3, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(1, 'Fixture & Technology Installation', 'NOT_STARTED', '2026-05-31', NULL, NULL, 4, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(1, 'Final Walkthrough & Handoff', 'NOT_STARTED', '2026-06-30', NULL, NULL, 5, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- Project 2: Creative Design Co — Speakeasy Studio (PROPOSAL)
INSERT INTO project_milestone (project_id, name, status, due_date, completed_date, notes, sort_order, created_at, updated_at) VALUES
(2, 'Site Assessment & Measurements', 'NOT_STARTED', '2026-07-08', NULL, NULL, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(2, 'Theme Design & Customer Approval', 'NOT_STARTED', '2026-07-22', NULL, NULL, 2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(2, 'Construction & Structural Work', 'NOT_STARTED', '2026-08-15', NULL, NULL, 3, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(2, 'Fixture & Technology Installation', 'NOT_STARTED', '2026-09-10', NULL, NULL, 4, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(2, 'Final Walkthrough & Handoff', 'NOT_STARTED', '2026-09-30', NULL, NULL, 5, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- Project 3: Handcrafted Furniture — Zen Showroom (COMPLETED)
INSERT INTO project_milestone (project_id, name, status, due_date, completed_date, notes, sort_order, created_at, updated_at) VALUES
(3, 'Site Assessment & Measurements', 'COMPLETED', '2026-01-22', '2026-01-21', 'Building B layout ideal for zen garden. Natural light from skylights is excellent.', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(3, 'Theme Design & Customer Approval', 'COMPLETED', '2026-02-05', '2026-02-03', 'Patricia approved bonsai garden with koi pond centerpiece. Upgraded to premium water feature.', 2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(3, 'Construction & Structural Work', 'COMPLETED', '2026-02-20', '2026-02-18', 'Bamboo flooring and stone pathways installed. Plumbing for water features complete.', 3, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(3, 'Fixture & Technology Installation', 'COMPLETED', '2026-03-05', '2026-03-03', 'Smart lighting, sound system, and meditation nook partitions installed.', 4, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(3, 'Final Walkthrough & Handoff', 'COMPLETED', '2026-03-15', '2026-03-10', 'Customer accepted. Warranty briefing delivered. Outstanding feedback from Patricia.', 5, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- Project 4: Brew & Bean — Enchanted Forest Lounge (APPROVED)
INSERT INTO project_milestone (project_id, name, status, due_date, completed_date, notes, sort_order, created_at, updated_at) VALUES
(4, 'Site Assessment & Measurements', 'COMPLETED', '2026-04-15', '2026-04-12', 'Second floor space measured. Load-bearing check passed for waterfall installation.', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(4, 'Theme Design & Customer Approval', 'NOT_STARTED', '2026-05-01', NULL, NULL, 2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(4, 'Construction & Structural Work', 'NOT_STARTED', '2026-06-01', NULL, NULL, 3, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(4, 'Fixture & Technology Installation', 'NOT_STARTED', '2026-07-01', NULL, NULL, 4, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(4, 'Final Walkthrough & Handoff', 'NOT_STARTED', '2026-07-31', NULL, NULL, 5, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- Project 5: Mind & Body Wellness — Custom Meditation Suite (IN_PROGRESS)
INSERT INTO project_milestone (project_id, name, status, due_date, completed_date, notes, sort_order, created_at, updated_at) VALUES
(5, 'Site Assessment & Measurements', 'COMPLETED', '2026-02-22', '2026-02-21', 'Unit 3 assessed. Good acoustics. HVAC adequate for aromatherapy system.', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(5, 'Theme Design & Customer Approval', 'COMPLETED', '2026-03-08', '2026-03-06', 'Custom design approved: floating meditation pods, chromotherapy lighting, and Himalayan salt wall.', 2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(5, 'Construction & Structural Work', 'IN_PROGRESS', '2026-04-15', NULL, 'Sound insulation and aromatherapy ductwork in progress. Salt wall foundation poured.', 3, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(5, 'Fixture & Technology Installation', 'NOT_STARTED', '2026-05-10', NULL, NULL, 4, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(5, 'Final Walkthrough & Handoff', 'NOT_STARTED', '2026-05-31', NULL, NULL, 5, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- =====================================================
-- Project Notes
-- =====================================================
INSERT INTO project_note (project_id, note_text, note_type, author, created_at) VALUES
-- Project 1: Tech Solutions IT — Interstellar Ops Center (IN_PROGRESS)
(1, 'Initial site visit completed. The 4th floor has 14-foot ceilings — perfect for the star field installation. Electrical panel has capacity for holographic projectors.', 'SITE_VISIT', 'Jordan Blake', CURRENT_TIMESTAMP),
(1, 'Customer requested upgrade from standard to premium holographic display package. Budget impact: +$35,000. Change order approved by David Rodriguez.', 'CHANGE_ORDER', 'Sally Sellers', CURRENT_TIMESTAMP),
(1, 'Construction phase progressing on schedule. Electrical upgrades 60% complete. Sound-dampening wall panels arriving next week.', 'STATUS_UPDATE', 'Jordan Blake', CURRENT_TIMESTAMP),

-- Project 2: Creative Design Co — Speakeasy Studio (PROPOSAL)
(2, 'Initial concept discussion with Lisa Martinez. She wants authentic 1920s details: hidden door entrance, art deco fixtures, and period-appropriate jazz speaker system.', 'GENERAL', 'Jordan Blake', CURRENT_TIMESTAMP),

-- Project 3: Handcrafted Furniture — Zen Showroom (COMPLETED)
(3, 'Walkthrough with Patricia Davis. She loved the koi pond centerpiece. Requested one minor adjustment to meditation nook lighting — warmer color temperature.', 'SITE_VISIT', 'Marcus Fleming', CURRENT_TIMESTAMP),
(3, 'Customer requested upgrade to premium sound system with nature soundscape library. Additional cost $8,500 approved.', 'CHANGE_ORDER', 'Marcus Fleming', CURRENT_TIMESTAMP),
(3, 'Project completed and handed off. Patricia Davis signed acceptance. Warranty documentation delivered. She is already referring us to other Nashville businesses.', 'STATUS_UPDATE', 'Marcus Fleming', CURRENT_TIMESTAMP),

-- Project 4: Brew & Bean — Enchanted Forest Lounge (APPROVED)
(4, 'Site assessment complete. Load-bearing structure verified for waterfall installation. Sarah Johnson enthusiastic about the living wall concept.', 'SITE_VISIT', 'Sally Sellers', CURRENT_TIMESTAMP),
(4, 'Project approved by Sarah Johnson. Contract signed. Awaiting scheduling for design phase kickoff in May.', 'STATUS_UPDATE', 'Sally Sellers', CURRENT_TIMESTAMP),

-- Project 5: Mind & Body Wellness — Custom Meditation Suite (IN_PROGRESS)
(5, 'Site visit with Sophia Patel. Unit 3 has excellent natural acoustics. HVAC system can support aromatherapy diffusion with minor modifications.', 'SITE_VISIT', 'Jordan Blake', CURRENT_TIMESTAMP),
(5, 'Sophia requested Himalayan salt wall addition to the meditation area. Custom feature adds $12,000 to budget. Approved by client.', 'CHANGE_ORDER', 'Jordan Blake', CURRENT_TIMESTAMP),
(5, 'Construction progressing well. Sound insulation installed in all pod chambers. Aromatherapy ductwork 40% complete. Salt wall foundation curing.', 'STATUS_UPDATE', 'Jordan Blake', CURRENT_TIMESTAMP),
(5, 'Supplier delay on chromotherapy LED panels. Expected 2-week delay on fixture installation phase. Communicated to Sophia — she is understanding.', 'ISSUE', 'Jordan Blake', CURRENT_TIMESTAMP);
