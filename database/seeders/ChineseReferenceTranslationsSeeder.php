<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;

class ChineseReferenceTranslationsSeeder extends Seeder
{
    public function run(): void
    {
        $this->merge('campuses', 1, 'name', ['zh' => '內部']);

        $this->mergeMany('enrollment_status_types', 'name', [
            1 => ['zh' => '待付款'],
            2 => ['zh' => '已付款'],
            3 => ['zh' => '已取消'],
            4 => ['zh' => '已轉移'],
            5 => ['zh' => '已退款'],
        ]);

        $this->mergeMany('result_types', 'name', [
            1 => ['zh' => '通過'],
            2 => ['zh' => '未通過'],
            3 => ['zh' => '請洽教務'],
        ]);

        $this->mergeMany('result_types', 'description', [
            1 => ['zh' => '可升讀下一級'],
            2 => ['zh' => '不可升讀下一級'],
            3 => ['zh' => '請與教務部門確認結果'],
        ]);

        $this->mergeMany('attendance_types', 'name', [
            1 => ['zh' => '出席'],
            2 => ['zh' => '部分出席'],
            3 => ['zh' => '已請假'],
            4 => ['zh' => '缺席'],
        ]);

        $this->mergeMany('contact_relationships', 'name', [
            1 => ['zh' => '家人'],
            2 => ['zh' => '工作'],
        ]);

        $this->mergeMany('skill_scales', 'shortname', [
            1 => ['zh' => '否'],
            2 => ['zh' => '進行中'],
            3 => ['zh' => '是'],
        ]);

        $this->mergeMany('skill_scales', 'name', [
            1 => ['zh' => '未掌握'],
            2 => ['zh' => '掌握中'],
            3 => ['zh' => '已掌握'],
        ]);

        $this->mergeMany('leave_types', 'name', [
            1 => ['zh' => '公眾假期'],
            2 => ['zh' => '休假'],
            3 => ['zh' => '特別假'],
            4 => ['zh' => '補假'],
            5 => ['zh' => '病假'],
        ]);
    }

    /**
     * @param  array<int, array<string, string>>  $translationsById
     */
    private function mergeMany(string $table, string $column, array $translationsById): void
    {
        foreach ($translationsById as $id => $translations) {
            $this->merge($table, $id, $column, $translations);
        }
    }

    /**
     * @param  array<string, string>  $translations
     */
    private function merge(string $table, int $id, string $column, array $translations): void
    {
        $row = DB::table($table)->where('id', $id)->first();

        if (! $row) {
            return;
        }

        $existing = json_decode((string) $row->{$column}, true);
        $existing = is_array($existing) ? $existing : [];

        DB::table($table)
            ->where('id', $id)
            ->update([$column => json_encode([...$existing, ...$translations], JSON_UNESCAPED_UNICODE)]);
    }
}
