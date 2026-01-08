#!/bin/bash
# Creates realistic test files for functional testing

set -e

TEST_DIR="$(cd "$(dirname "$0")" && pwd)/TestFiles"

echo "Creating test files in: $TEST_DIR"

# Clean existing files
rm -f "$TEST_DIR"/*.txt "$TEST_DIR"/*.pdf "$TEST_DIR"/*.jpg "$TEST_DIR"/*.mp4 "$TEST_DIR"/*.doc "$TEST_DIR"/*.xlsx

# Work Documents (15 files)
cat > "$TEST_DIR/Q4_2023_Sales_Report.txt" << 'EOF'
Q4 2023 Sales Report
Total Revenue: $1.2M
Growth: 15% YoY
EOF

cat > "$TEST_DIR/2024_Budget_Proposal.txt" << 'EOF'
2024 Budget Proposal
Requested: $500K
Department: Engineering
EOF

cat > "$TEST_DIR/Employee_Handbook_2024.txt" << 'EOF'
Employee Handbook
Version 2024.1
Policies and Procedures
EOF

echo "Meeting notes from January 15, 2024" > "$TEST_DIR/Meeting_Notes_Jan_15_2024.txt"
echo "Q1 Project Roadmap" > "$TEST_DIR/Project_Roadmap_Q1.txt"
echo "Client Presentation Draft" > "$TEST_DIR/Client_Presentation_Draft.txt"
echo "Contract Review - Legal Department" > "$TEST_DIR/Contract_Review_Legal.txt"
echo "Vendor Invoice - March 2024" > "$TEST_DIR/Vendor_Invoice_March_2024.txt"
echo "HR Policy Update" > "$TEST_DIR/HR_Policy_Update.txt"
echo "Team Performance Review" > "$TEST_DIR/Team_Performance_Review.txt"
echo "Annual Report 2023" > "$TEST_DIR/Annual_Report_2023.txt"
echo "Marketing Strategy 2024" > "$TEST_DIR/Marketing_Strategy_2024.txt"
echo "Product Requirements Document" > "$TEST_DIR/Product_Requirements_Doc.txt"
echo "Technical Specification v2" > "$TEST_DIR/Technical_Specification_v2.txt"
echo "Business Plan 2024" > "$TEST_DIR/Business_Plan_2024.txt"

# Personal Photos (12 files)
echo "JPEG Image Data" > "$TEST_DIR/IMG_20230615_Vacation_Beach.jpg"
echo "JPEG Image Data" > "$TEST_DIR/IMG_20230616_Sunset_View.jpg"
echo "JPEG Image Data" > "$TEST_DIR/IMG_20230720_Birthday_Party.jpg"
echo "JPEG Image Data" > "$TEST_DIR/PHOTO_Family_Reunion_2023.jpg"
echo "JPEG Image Data" > "$TEST_DIR/DSC_0001_Wedding_Ceremony.jpg"
echo "JPEG Image Data" > "$TEST_DIR/DSC_0002_Wedding_Reception.jpg"
echo "JPEG Image Data" > "$TEST_DIR/Graduation_Photo_2024.jpg"
echo "JPEG Image Data" > "$TEST_DIR/Christmas_2023_Family.jpg"
echo "JPEG Image Data" > "$TEST_DIR/New_Years_Eve_Party.jpg"
echo "JPEG Image Data" > "$TEST_DIR/Spring_Garden_Photos.jpg"
echo "JPEG Image Data" > "$TEST_DIR/Kids_School_Play.jpg"
echo "JPEG Image Data" > "$TEST_DIR/Portrait_Studio_Session.jpg"

# Videos (8 files)
echo "MP4 Video Data" > "$TEST_DIR/VID_20230801_Summer_Trip.mp4"
echo "MP4 Video Data" > "$TEST_DIR/VID_20230802_Beach_Waves.mp4"
echo "MP4 Video Data" > "$TEST_DIR/Movie_Night_Recording.mp4"
echo "MP4 Video Data" > "$TEST_DIR/Birthday_Celebration_Video.mp4"
echo "MP4 Video Data" > "$TEST_DIR/Tutorial_How_To_Code.mp4"
echo "MP4 Video Data" > "$TEST_DIR/Conference_Keynote_2024.mp4"
echo "MP4 Video Data" > "$TEST_DIR/Family_Vlog_Episode_1.mp4"
echo "MP4 Video Data" > "$TEST_DIR/Travel_Documentary_Europe.mp4"

# Music & Audio (10 files)
echo "Summer vibes song" > "$TEST_DIR/Song_Summer_Vibes.txt"
echo "Tech Talk podcast episode" > "$TEST_DIR/Podcast_Episode_Tech_Talk.txt"
echo "Audio book chapter 1" > "$TEST_DIR/Audio_Book_Chapter_1.txt"
echo "Workout music playlist" > "$TEST_DIR/Music_Playlist_Workout.txt"
echo "Voice memo with ideas" > "$TEST_DIR/Voice_Memo_Ideas.txt"
echo "Band practice recording" > "$TEST_DIR/Recording_Band_Practice.txt"
echo "Meditation audio guide" > "$TEST_DIR/Meditation_Audio_Guide.txt"
echo "Language learning lesson 5" > "$TEST_DIR/Language_Learning_Lesson_5.txt"
echo "CEO interview recording" > "$TEST_DIR/Interview_Recording_CEO.txt"
echo "Sound effects library" > "$TEST_DIR/Sound_Effects_Library.txt"

# Recipes & Food (8 files)
echo "Chocolate cake recipe" > "$TEST_DIR/Recipe_Chocolate_Cake.txt"
echo "Pasta carbonara recipe" > "$TEST_DIR/Recipe_Pasta_Carbonara.txt"
echo "Thai curry recipe" > "$TEST_DIR/Recipe_Thai_Curry.txt"
echo "Weekly meal plan" > "$TEST_DIR/Meal_Plan_Weekly.txt"
echo "Grocery shopping list" > "$TEST_DIR/Grocery_Shopping_List.txt"
echo "Restaurant recommendations" > "$TEST_DIR/Restaurant_Recommendations.txt"
echo "Italian dishes cookbook" > "$TEST_DIR/Cookbook_Italian_Dishes.txt"
echo "Keto diet plan" > "$TEST_DIR/Diet_Plan_Keto.txt"

# Educational (10 files)
echo "Physics study notes" > "$TEST_DIR/Study_Notes_Physics.txt"
echo "History lecture notes" > "$TEST_DIR/Lecture_Notes_History.txt"
echo "Math homework assignment" > "$TEST_DIR/Math_Homework_Assignment.txt"
echo "Climate change research paper" > "$TEST_DIR/Research_Paper_Climate_Change.txt"
echo "1984 book summary" > "$TEST_DIR/Book_Summary_1984.txt"
echo "Python course materials" > "$TEST_DIR/Course_Materials_Python.txt"
echo "Machine learning tutorial" > "$TEST_DIR/Tutorial_Machine_Learning.txt"
echo "Chemistry exam prep" > "$TEST_DIR/Exam_Prep_Chemistry.txt"
echo "Thesis draft chapter 3" > "$TEST_DIR/Thesis_Draft_Chapter_3.txt"
echo "Bibliography and references" > "$TEST_DIR/Bibliography_References.txt"

# Financial (9 files)
echo "Bank statement January 2024" > "$TEST_DIR/Bank_Statement_January_2024.txt"
echo "Tax return 2023" > "$TEST_DIR/Tax_Return_2023.txt"
echo "Investment portfolio summary" > "$TEST_DIR/Investment_Portfolio_Summary.txt"
echo "Mortgage documents" > "$TEST_DIR/Mortgage_Documents.txt"
echo "Auto insurance policy" > "$TEST_DIR/Insurance_Policy_Auto.txt"
echo "401k retirement plan" > "$TEST_DIR/Retirement_Plan_401k.txt"
echo "Credit card bill March" > "$TEST_DIR/Credit_Card_Bill_March.txt"
echo "Q1 2024 expense report" > "$TEST_DIR/Expense_Report_Q1_2024.txt"
echo "Savings account summary" > "$TEST_DIR/Savings_Account_Summary.txt"

# Health & Fitness (8 files)
echo "Monday workout routine" > "$TEST_DIR/Workout_Routine_Monday.txt"
echo "Fitness tracker data" > "$TEST_DIR/Fitness_Tracker_Data.txt"
echo "Weekly nutrition log" > "$TEST_DIR/Nutrition_Log_Weekly.txt"
echo "Medical records 2024" > "$TEST_DIR/Medical_Records_2024.txt"
echo "Prescription information" > "$TEST_DIR/Prescription_Information.txt"
echo "Yoga class schedule" > "$TEST_DIR/Yoga_Class_Schedule.txt"
echo "Running training plan" > "$TEST_DIR/Running_Training_Plan.txt"
echo "Health insurance info" > "$TEST_DIR/Health_Insurance_Info.txt"

# Travel (10 files)
echo "Flight booking confirmation" > "$TEST_DIR/Flight_Booking_Confirmation.txt"
echo "Hotel reservation Paris" > "$TEST_DIR/Hotel_Reservation_Paris.txt"
echo "Europe 2024 travel itinerary" > "$TEST_DIR/Travel_Itinerary_Europe_2024.txt"
echo "Passport copy scan" > "$TEST_DIR/Passport_Copy_Scan.txt"
echo "Vacation packing list" > "$TEST_DIR/Vacation_Packing_List.txt"
echo "Travel insurance policy" > "$TEST_DIR/Travel_Insurance_Policy.txt"
echo "Tokyo city guide" > "$TEST_DIR/City_Guide_Tokyo.txt"
echo "Road trip route planning" > "$TEST_DIR/Road_Trip_Route_Planning.txt"
echo "Travel photos backup list" > "$TEST_DIR/Travel_Photos_Backup_List.txt"
echo "Visa application documents" > "$TEST_DIR/Visa_Application_Documents.txt"

# Random/Misc (10 files)
echo "Random notes and ideas" > "$TEST_DIR/Random_Notes_Ideas.txt"
echo "General todo list" > "$TEST_DIR/Todo_List_General.txt"
echo "Inspirational quotes" > "$TEST_DIR/Quotes_Inspiration.txt"
echo "Journal entry March 2024" > "$TEST_DIR/Journal_Entry_March_2024.txt"
echo "Dream log 2024" > "$TEST_DIR/Dream_Log_2024.txt"
echo "Birthday gift ideas" > "$TEST_DIR/Gift_Ideas_Birthday.txt"
echo "Home improvement projects" > "$TEST_DIR/Home_Improvement_Projects.txt"
echo "Car maintenance schedule" > "$TEST_DIR/Car_Maintenance_Schedule.txt"
echo "Garden planting guide" > "$TEST_DIR/Garden_Planting_Guide.txt"
echo "Pet care instructions" > "$TEST_DIR/Pet_Care_Instructions.txt"

echo "✅ Created $(ls -1 "$TEST_DIR" | wc -l) test files"
echo ""
echo "Category breakdown:"
echo "- Work Documents: 15 files"
echo "- Personal Photos: 12 files"
echo "- Videos: 8 files"
echo "- Music & Audio: 10 files"
echo "- Recipes & Food: 8 files"
echo "- Educational: 10 files"
echo "- Financial: 9 files"
echo "- Health & Fitness: 8 files"
echo "- Travel: 10 files"
echo "- Misc/Random: 10 files"
echo "Total: 100 files"

