<?php

use Symfony\Component\VarDumper\VarDumper;
use Symfony\Component\Yaml\Yaml;

if (!function_exists('installed')) {
    function installed($name)
    {
        if (shell_exec("command -v $name") != '') {
            return true;
        }

        return false;
    }
}

if (!function_exists('base_path')) {
    function base_path($path = '')
    {
        return __DIR__ . "/../../$path";
    }
}

if (!function_exists('resource_path')) {
    function resource_path($path = '')
    {
        return __DIR__ . "/../Resources/$path";
    }
}

if (!function_exists('str_contains')) {
    function str_contains($haystack, $needles)
    {
        foreach ((array)$needles as $needle) {
            if ($needle != '' && mb_strpos($haystack, $needle) !== false) {
                return true;
            }
        }

        return false;
    }
}

if (!function_exists('str_random')) {
    /**
     * Generate a more truly "random" alpha-numeric string.
     *
     * @param  int $length
     * @return string
     */
    function str_random($length = 16)
    {
        $string = '';

        while (($len = strlen($string)) < $length) {
            $size = $length - $len;

            $bytes = random_bytes($size);

            $string .= substr(str_replace(['/', '+', '='], '', base64_encode($bytes)), 0, $size);
        }

        return $string;
    }
}

if (!function_exists('fqdn')) {
    function fqdn()
    {
        return trim(exec('hostname -f'));
    }
}

if (!function_exists('hostname')) {
    function hostname()
    {
        return trim(exec('hostname'));
    }
}

if (!function_exists('ip')) {
    function ip()
    {
        return trim(explode(' ', exec('hostname -I'))[0]);
    }
}

if (!function_exists('dd')) {
    function dd($var)
    {
        VarDumper::dump($var);
        die();
    }
}

if (!function_exists('array_find')) {
    function array_find($array, $searchKey = '')
    {
        //create a recursive iterator to loop over the array recursively
        $iter = new RecursiveIteratorIterator(
            new RecursiveArrayIterator($array),
            RecursiveIteratorIterator::SELF_FIRST);

        //loop over the iterator
        foreach ($iter as $key => $value) {
            //if the key matches our search
            if ($key === $searchKey) {
                //add the current key
                $keys = array($key);
                //loop up the recursive chain
                for ($i = $iter->getDepth() - 1; $i >= 0; $i--) {
                    //add each parent key
                    array_unshift($keys, $iter->getSubIterator($i)->key());
                }
                //return our output array
                return array('path' => implode('.', $keys), 'value' => $value);
            }
        }

        //return false if not found
        return false;
    }
}

if (!function_exists('distinfo')) {
    function distinfo()
    {
        $distname = strtolower(trim(shell_exec('head -n1 /etc/issue | cut -f 1 -d \' \'')));
        $distver = trim(shell_exec('head -n1 /etc/issue | cut -f 2 -d \' \''));
        $lts = (trim(shell_exec('head -n1 /etc/issue | cut -f 3 -d \' \'') === 'LTS'));

        preg_match("/^[0-9]..[0-9]./m", $distver, $matches);
        $mainver = $matches[0];

        switch ($mainver) {
            case "24.04":
                $relname = "(Noble Numbat)";
                break;
            case "22.04":
                $relname = "(Jammy Jellyfish)";
                break;
            case "20.04":
                $relname = "(Focal Fossa)";
                break;
            default:
                $relname = "UNKNOWN";
        }

        return array(
            'name' => $distname,
            'version' => $distver,
            'mainver' => $mainver,
            'relname' => $relname,
            'lts' => $lts
        );
    }
}

if (!function_exists('distname')) {
    function distname()
    {
        return strtolower(distinfo()['name']);
    }
}

if (!function_exists('distversion')) {
    function distversion()
    {
        return strtolower(distinfo()['version']);
    }
}

if (!function_exists('distmainver')) {
    function distmainver()
    {
        return strtolower(distinfo()['mainver']);
    }
}

if (!function_exists('distrelname')) {
    function distrelname()
    {
        return strtolower(distinfo()['name']);
    }
}

if (!function_exists('distlts')) {
    function distlts()
    {
        return strtolower(distinfo()['lts']);
    }
}

if (!function_exists('memory')) {
    function memory()
    {
        return shell_exec("grep 'MemTotal' /proc/meminfo |tr ' ' '\n' |grep [0-9]") != '';
    }
}
