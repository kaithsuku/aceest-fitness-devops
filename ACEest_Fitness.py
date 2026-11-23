"""Fitness programs adapted from the supplied Aceestver-1.0.py."""

from dataclasses import dataclass


@dataclass(frozen=True)
class Program:
    code: str
    name: str
    workout: str
    nutrition: str


PROGRAMS = {
    "fl": Program(
        "fl",
        "Fat Loss (FL)",
        "Mon: 5x5 Back Squat + AMRAP\n"
        "Tue: EMOM 20min Assault Bike\n"
        "Wed: Bench Press + 21-15-9\n"
        "Thu: 10RFT Deadlifts/Box Jumps\n"
        "Fri: 30min Active Recovery",
        "B: 3 Egg Whites + Oats Idli\n"
        "L: Grilled Chicken + Brown Rice\n"
        "D: Fish Curry + Millet Roti\n"
        "Target: 2,000 kcal",
    ),
    "mg": Program(
        "mg",
        "Muscle Gain (MG)",
        "Mon: Squat 5x5\n"
        "Tue: Bench 5x5\n"
        "Wed: Deadlift 4x6\n"
        "Thu: Front Squat 4x8\n"
        "Fri: Incline Press 4x10\n"
        "Sat: Barbell Rows 4x10",
        "B: 4 Eggs + PB Oats\n"
        "L: Chicken Biryani (250g Chicken)\n"
        "D: Mutton Curry + Jeera Rice\n"
        "Target: 3,200 kcal",
    ),
    "bg": Program(
        "bg",
        "Beginner (BG)",
        "Circuit Training: Air Squats, Ring Rows, Push-ups.\n"
        "Focus: Technique Mastery & Form (90% Threshold)",
        "Balanced Tamil Meals: Idli-Sambar, Rice-Dal, Chapati.\n"
        "Protein: 120g/day",
    ),
}
