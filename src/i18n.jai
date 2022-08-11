I18N_Lang :: enum {
    EN;
    RU;
    UA;
    HU;
    ES;
    GL;
    BY;
    FR;
    IT;
    PH;
    PL;
    DE;
    JA;
}
I18N_LANG_COUNT :: #run type_info(I18N_Lang).names.count;

I18N_Text :: enum {
    PRESS_SPACE_TO_RESTART;
    PAUSE;
    PRESS_ARROWS_LEFT_OR_RIGHT_TO_MOVE_AROUND;
    PRESS_SPACE_TO_START;
    GAME_OVER;
    SCORE;
}
I18N_TEXT_COUNT :: #run type_info(I18N_Text).names.count;
